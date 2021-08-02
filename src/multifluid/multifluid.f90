! Copyright 2021 Matthew Zettergren

! Licensed under the Apache License, Version 2.0 (the "License");
! you may not use this file except in compliance with the License.
! You may obtain a copy of the License at
!
!   http://www.apache.org/licenses/LICENSE-2.0

! Unless required by applicable law or agreed to in writing, software
! distributed under the License is distributed on an "AS IS" BASIS,
! WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
! See the License for the specific language governing permissions and
! limitations under the License.

module multifluid

use, intrinsic :: ieee_arithmetic, only : ieee_is_nan

use advec_mpi, only: advec3d_mc_mpi, advec_prep_mpi
use calculus, only: etd_uncoupled, div3d
use collisions, only:  thermal_conduct
use phys_consts, only : wp,pi,qs,lsp,gammas,kB,ms,mindensdiv,mindens,mindensnull, debug
use diffusion, only:  trbdf23d, diffusion_prep, backEuler3D
use grid, only: lx1, lx2, lx3, gridflag
use meshobj, only: curvmesh
use ionization, only: ionrate_glow98, ionrate_fang, eheating, photoionization
use mpimod, only: mpi_cfg, tag=>gemini_mpi
use precipBCs_mod, only: precipBCs_fileinput, precipBCs
use sources, only: rk2_prep_mpi, srcsenergy, srcsmomentum, srcscontinuity
use timeutils, only : sza
use config, only: gemini_cfg

implicit none (type, external)
private
public :: fluid_adv

integer, parameter :: lprec=2
!! number of precipitating electron populations

real(wp), allocatable, dimension(:,:,:,:) :: PrPrecipG
real(wp), allocatable, dimension(:,:,:) :: QePrecipG, iverG

contains

subroutine fluid_adv(ns,vs1,Ts,vs2,vs3,J1,E1,cfg,t,dt,x,nn,vn1,vn2,vn3,Tn,iver,ymd,UTsec, first)
!! J1 needed for heat conduction; E1 for momentum equation

!! THIS SUBROUTINE ADVANCES ALL OF THE FLUID VARIABLES BY TIME STEP DT.

real(wp), dimension(-1:,-1:,-1:,:), intent(inout) ::  ns,vs1,Ts
real(wp), dimension(-1:,-1:,-1:,:), intent(inout) ::  vs2,vs3
real(wp), dimension(:,:,:), intent(in) :: J1
!! needed for thermal conduction in electron population
real(wp), dimension(:,:,:), intent(inout) :: E1
!! will have ambipolar field added into it in this procedure...

type(gemini_cfg), intent(in) :: cfg
real(wp), intent(in) :: t,dt

class(curvmesh), intent(in) :: x
!! grid structure variable

real(wp), dimension(:,:,:,:), intent(in) :: nn
real(wp), dimension(:,:,:), intent(in) :: vn1,vn2,vn3,Tn
integer, dimension(3), intent(in) :: ymd
real(wp), intent(in) :: UTsec
logical, intent(in) :: first  !< first time step

real(wp), dimension(:,:,:), intent(inout) :: iver
!! intent(out)

integer :: isp
real(wp) :: tstart,tfin

real(wp) :: f107,f107a

real(wp), dimension(-1:size(ns,1)-2,-1:size(ns,2)-2,-1:size(ns,3)-2,size(ns,4)) ::  rhovs1,rhoes
real(wp), dimension(-1:size(ns,1)-2,-1:size(ns,2)-2,-1:size(ns,3)-2) :: param
real(wp), dimension(-1:size(ns,1)-2,-1:size(ns,2)-2,-1:size(ns,3)-2) :: chrgflux
real(wp), dimension(1:size(ns,1)-4,1:size(ns,2)-4,1:size(ns,3)-4) :: A,B,C,D,E,paramtrim,rhoeshalf,lambda,beta!,chrgflux
real(wp), dimension(0:size(ns,1)-3,0:size(ns,2)-3,0:size(ns,3)-3) :: divvs
real(wp), dimension(1:size(vs1,1)-3,1:size(vs1,2)-4,1:size(vs1,3)-4) :: v1i
real(wp), dimension(1:size(vs1,1)-4,1:size(vs1,2)-3,1:size(vs1,3)-4) :: v2i
real(wp), dimension(1:size(vs1,1)-4,1:size(vs1,2)-4,1:size(vs1,3)-3) :: v3i

real(wp), dimension(1:size(ns,1)-4,1:size(ns,2)-4,1:size(ns,3)-4,size(ns,4)) :: Pr,Lo
real(wp), dimension(1:size(ns,1)-4,1:size(ns,2)-4,1:size(ns,3)-4,size(ns,4)-1) :: Prprecip,Prpreciptmp
real(wp), dimension(1:size(ns,1)-4,1:size(ns,2)-4,1:size(ns,3)-4) :: Qeprecip,Qepreciptmp
real(wp), dimension(1:size(ns,1)-4,1:size(ns,2)-4,1:size(ns,3)-4) :: chi
real(wp), dimension(1:size(ns,2)-4,1:size(ns,3)-4,lprec) :: W0,PhiWmWm2

integer :: iprec
real(wp), dimension(1:size(vs1,1)-3,1:size(vs1,2)-4,1:size(vs1,3)-4) :: v1iupdate
!! temp interface velocities for art. viscosity
real(wp), dimension(1:size(vs1,1)-4,1:size(vs1,2)-4,1:size(vs1,3)-4) :: dv1iupdate
!! interface diffs. for art. visc.
real(wp), dimension(1:size(ns,1)-4,1:size(ns,2)-4,1:size(ns,3)-4,size(ns,4)) :: Q
real(wp), parameter :: xicon = 3
!! artificial viscosity, decent value for closed field-line grids extending to high altitudes, can be set to 0 for cartesian simulations not exceed altitudes of 1500 km.


!> MAKING SURE THESE ARRAYS ARE ALWAYS IN SCOPE.  FIXME: should only be done if first=.true. right???
if ((cfg%flagglow/=0).and.(.not.allocated(PrprecipG))) then
  allocate(PrprecipG(1:size(ns,1)-4,1:size(ns,2)-4,1:size(ns,3)-4,size(ns,4)-1))
  PrprecipG(:,:,:,:)=0
end if
if ((cfg%flagglow/=0).and.(.not.allocated(QeprecipG))) then
  allocate(QeprecipG(1:size(ns,1)-4,1:size(ns,2)-4,1:size(ns,3)-4))
  QeprecipG(:,:,:)=0
end if
if ((cfg%flagglow/=0).and.(.not.allocated(iverG))) then
  allocate(iverG(size(iver,1),size(iver,2),size(iver,3)))
  iverG(:,:,:)=0
end if


! cfg arrays can be confusing, particularly f107, so assign to sensible variable name here
f107=cfg%activ(2)
f107a=cfg%activ(1)


!CALCULATE THE INTERNAL ENERGY AND MOMENTUM FLUX DENSITIES (ADVECTION AND SOURCE SOLUTIONS ARE DONE IN THESE VARIABLES)
do isp=1,lsp
  rhovs1(:,:,:,isp)=ns(:,:,:,isp)*ms(isp)*vs1(:,:,:,isp)
  rhoes(:,:,:,isp)=ns(:,:,:,isp)*kB*Ts(:,:,:,isp)/(gammas(isp) - 1)
end do


!ADVECTION SUBSTEP (CONSERVED VARIABLES SHOULD BE UPDATED BEFORE ENTERING)
call cpu_time(tstart)
chrgflux = 0
do isp=1,lsp
  call advec_prep_mpi(isp,x%flagper,ns,rhovs1,vs1,vs2,vs3,rhoes,v1i,v2i,v3i)    !role-agnostic communication pattern (all-to-neighbors)

  if(isp<lsp) then   !electron info found from charge neutrality and current density
    param=ns(:,:,:,isp)
    param=advec3D_MC_mpi(param,v1i,v2i,v3i,dt,x,0,tag%ns)   !second to last argument is tensor rank of thing being advected
    ns(:,:,:,isp)=param

    param=rhovs1(:,:,:,isp)
    param=advec3D_MC_mpi(param,v1i,v2i,v3i,dt,x,1,tag%vs1)
    rhovs1(:,:,:,isp)=param

    vs1(:,:,:,isp)=rhovs1(:,:,:,isp)/(ms(isp)*max(ns(:,:,:,isp),mindensdiv))
    chrgflux=chrgflux+ns(:,:,:,isp)*qs(isp)*vs1(:,:,:,isp)
  else
    ns(:,:,:,lsp)=sum(ns(:,:,:,1:lsp-1),4)
!      vs1(1:lx1,1:lx2,1:lx3,lsp)=1/ns(1:lx1,1:lx2,1:lx3,lsp)/qs(lsp)*(J1-chrgflux)   !density floor needed???
    vs1(:,:,:,lsp)=-1/max(ns(:,:,:,lsp),mindensdiv)/qs(lsp)*chrgflux   !really not strictly correct, should include current density
  end if

  param=rhoes(:,:,:,isp)
  param=advec3D_MC_mpi(param,v1i,v2i,v3i,dt,x,0,tag%Ts)
  rhoes(:,:,:,isp)=param
end do

if (mpi_cfg%myid==0 .and. debug) then
  call cpu_time(tfin)
  print *, 'Completed advection substep for time step:  ',t,' in cpu_time of:  ',tfin-tstart
end if


!CLEAN DENSITY AND VELOCITY - SETS THE NULL CELLS TO SOME SENSIBLE VALUE SO
!THEY DON'T MESS UP FINITE DIFFERENCES LATER
call clean_param(x,1,ns)
call clean_param(x,2,vs1)


!ARTIFICIAL VISCOSITY (NOT REALLY NEED BELOW 1000 KM ALT.).  NOTE THAT WE DON'T CHECK WHERE SUBCYCLING IS NEEDED SINCE, IN MY EXPERIENCE THEN CODE IS BOMBING ANYTIME IT IS...
! Interestingly, this is accessing ghost cells of velocity so if they are overwritten by clean_params this viscosity calculation would generate "odd" results
do isp=1,lsp-1
  v1iupdate(1:lx1+1,:,:)=0.5_wp*(vs1(0:lx1,1:lx2,1:lx3,isp)+vs1(1:lx1+1,1:lx2,1:lx3,isp))    !compute an updated interface velocity (only in x1-direction)
  dv1iupdate=v1iupdate(2:lx1+1,:,:)-v1iupdate(1:lx1,:,:)
  Q(:,:,:,isp)=ns(1:lx1,1:lx2,1:lx3,isp)*ms(isp)*0.25_wp*xicon**2*(min(dv1iupdate,0._wp))**2   !note that viscosity does not have/need ghost cells
end do
Q(:,:,:,lsp) = 0


!NONSTIFF/NONBALANCE INTERNAL ENERGY SOURCES (RK2 INTEGRATION)
call cpu_time(tstart)
do isp=1,lsp
  call RK2_prep_mpi(isp,x%flagper,vs1,vs2,vs3)    !role-agnostic mpi, all-to-neighbor

  divvs = div3D(vs1(0:lx1+1,0:lx2+1,0:lx3+1,isp),&
                vs2(0:lx1+1,0:lx2+1,0:lx3+1,isp), &
                vs3(0:lx1+1,0:lx2+1,0:lx3+1,isp),x,0,lx1+1,0,lx2+1,0,lx3+1)
  !! diff with one set of ghost cells to preserve second order accuracy over the grid
  paramtrim=rhoes(1:lx1,1:lx2,1:lx3,isp)

  rhoeshalf = paramtrim - dt/2 * (paramtrim*(gammas(isp)-1) + Q(:,:,:,isp)) * divvs(1:lx1,1:lx2,1:lx3)
  !! t+dt/2 value of internal energy, use only interior points of divvs for second order accuracy

  paramtrim=paramtrim-dt*(rhoeshalf*(gammas(isp) - 1)+Q(:,:,:,isp))*divvs(1:lx1,1:lx2,1:lx3)
  rhoes(1:lx1,1:lx2,1:lx3,isp)=paramtrim

  Ts(:,:,:,isp)=(gammas(isp) - 1)/kB*rhoes(:,:,:,isp)/max(ns(:,:,:,isp),mindensdiv)
  Ts(:,:,:,isp)=max(Ts(:,:,:,isp), 100._wp)
end do

!> NaN check - FIXME: superfluous???
!if (any(ieee_is_nan(Ts))) error stop 'multifluid:fluid_adv: NaN detected in Ts after div3D()'

if (mpi_cfg%myid==0 .and. debug) then
  call cpu_time(tfin)
  print *, 'Completed compression substep for time step:  ',t,' in cpu_time of:  ',tfin-tstart
end if

!CLEAN TEMPERATURE
call clean_param(x,3,Ts)


!DIFFUSION OF ENERGY
call cpu_time(tstart)
do isp=1,lsp
  param=Ts(:,:,:,isp)     !temperature for this species
  call thermal_conduct(isp,param,ns(:,:,:,isp),nn,J1,lambda,beta)

  call diffusion_prep(isp,x,lambda,beta,ns(:,:,:,isp),param,A,B,C,D,E,Tn,cfg%Teinf)
  select case (cfg%diffsolvetype)
    case (1)
      param=backEuler3D(param,A,B,C,D,E,dt,x)    !1st order method, only use if you are seeing grid-level oscillations in temperatures
    case (2)
      param=TRBDF23D(param,A,B,C,D,E,dt,x)       !2nd order method, should be used for most simulations
    case default
      print*, 'Unsupported diffusion solver type/mode:  ',cfg%diffsolvetype,'.  Should be either 1 or 2.'
      error stop
  end select

  Ts(:,:,:,isp) = param
  Ts(:,:,:,isp) = max(Ts(:,:,:,isp), 100._wp)
end do

if (mpi_cfg%myid==0 .and. debug) then
  call cpu_time(tfin)
  print *, 'Completed energy diffusion substep for time step:  ',t,' in cpu_time of:  ',tfin-tstart
end if

!ZZZ - CLEAN TEMPERATURE BEFORE CONVERTING TO INTERNAL ENERGY
call clean_param(x,3,Ts)
do isp=1,lsp
  rhoes(:,:,:,isp)=ns(:,:,:,isp)*kB*Ts(:,:,:,isp)/(gammas(isp) - 1)
end do


!> LOAD ELECTRON PRECIPITATION PATTERN
if (cfg%flagprecfile==1) then
  call precipBCs_fileinput(dt,t,cfg,ymd,UTsec,x,W0,PhiWmWm2)
else
  !! no file input specified, so just call 'regular' function
  call precipBCs(t,x,cfg,W0,PhiWmWm2)
end if


!STIFF/BALANCED ENERGY SOURCES
call cpu_time(tstart)
Prprecip=0
Qeprecip=0
Prpreciptmp=0
Qepreciptmp=0
if (gridflag/=0) then
  if (cfg%flagglow==0) then
    !! RUN FANG APPROXIMATION
    do iprec=1,lprec
      !! loop over the different populations of precipitation (2 here?), accumulating production rates
      Prpreciptmp = ionrate_fang(W0(:,:,iprec), PhiWmWm2(:,:,iprec), x%alt, nn, Tn, cfg%flag_fang)
      !! calculation based on Fang et al [2008]
      Prprecip=Prprecip+Prpreciptmp
    end do
    Prprecip = max(Prprecip, 1e-5_wp)
    Qeprecip = eheating(nn,Tn,Prprecip,ns)
  else
    !! GLOW USED, AURORA PRODUCED
    if (int(t/cfg%dtglow)/=int((t+dt)/cfg%dtglow) .or. first) then
      if (mpi_cfg%myid==0) print*, 'Note:  preparing to call GLOW...  This could take a while if your grid is large...'
      PrprecipG=0; QeprecipG=0; iverG=0;
      call ionrate_glow98(W0,PhiWmWm2,ymd,UTsec,f107,f107a,x%glat(1,:,:),x%glon(1,:,:),x%alt,nn,Tn,ns,Ts, &
                          QeprecipG, iverG, PrprecipG)
      PrprecipG=max(PrprecipG, 1e-5_wp)
    end if
    Prprecip=PrprecipG
    Qeprecip=QeprecipG
    iver=iverG
  end if
else
  !! do not compute impact ionization on a closed mesh (presumably there is no source of energetic electrons at these lats.)
  if (mpi_cfg%myid==0 .and. debug) then
    print *, 'Looks like we have a closed grid, so skipping impact ionization for time step:  ',t
  end if
end if

if (mpi_cfg%myid==0) then
  if (debug) print *, 'Min/max root electron impact ionization production rates for time:  ',t,' :  ', &
    minval(Prprecip), maxval(Prprecip)
end if

if ((cfg%flagglow /= 0).and.(mpi_cfg%myid == 0)) then
  if (debug) print *, 'Min/max 427.8 nm emission column-integrated intensity for time:  ',t,' :  ', &
    minval(iver(:,:,2)), maxval(iver(:,:,2))
end if

!> now add in photoionization sources
chi=sza(ymd(1), ymd(2), ymd(3), UTsec,x%glat,x%glon)
if (mpi_cfg%myid==0 .and. debug) then
  print *, 'Computing photoionization for time:  ',t,' using sza range of (root only):  ', &
    minval(chi)*180/pi, maxval(chi)*180/pi
end if

Prpreciptmp=photoionization(x,nn,chi,f107,f107a,UTsec)

if (mpi_cfg%myid==0 .and. debug) then
  print *, 'Min/max root photoionization production rates for time:  ',t,' :  ', &
    minval(Prpreciptmp), maxval(Prpreciptmp)
end if

Prpreciptmp = max(Prpreciptmp, 1e-5_wp)
!! enforce minimum production rate to preserve conditioning for species that rely on constant production
!! testing should probably be done to see what the best choice is...

Qepreciptmp = eheating(nn,Tn,Prpreciptmp,ns)
!! thermal electron heating rate from Swartz and Nisbet, (1978)

!> photoion ionrate and heating calculated separately, added together with ionrate and heating from Fang or GLOW
Prprecip = Prprecip + Prpreciptmp
Qeprecip = Qeprecip + Qepreciptmp

call srcsEnergy(nn,vn1,vn2,vn3,Tn,ns,vs1,vs2,vs3,Ts,Pr,Lo)

do isp=1,lsp
  if (isp==lsp) then
    Pr(:,:,:,lsp)=Pr(:,:,:,lsp)+Qeprecip
  end if
  paramtrim=rhoes(1:lx1,1:lx2,1:lx3,isp)
  paramtrim=ETD_uncoupled(paramtrim,Pr(:,:,:,isp),Lo(:,:,:,isp),dt)
  rhoes(1:lx1,1:lx2,1:lx3,isp)=paramtrim

  Ts(:,:,:,isp)=(gammas(isp) - 1)/kB*rhoes(:,:,:,isp)/max(ns(:,:,:,isp),mindensdiv)
  Ts(:,:,:,isp)=max(Ts(:,:,:,isp), 100._wp)
end do

if (mpi_cfg%myid==0 .and. debug) then
  call cpu_time(tfin)
  print *, 'Energy sources substep for time step:  ',t,'done in cpu_time of:  ',tfin-tstart
end if

!CLEAN TEMPERATURE
call clean_param(x,3,Ts)


!ALL VELOCITY SOURCES
call cpu_time(tstart)
call srcsMomentum(nn,vn1,Tn,ns,vs1,vs2,vs3,Ts,E1,Q,x,Pr,Lo)    !added artificial viscosity...
do isp=1,lsp-1
  paramtrim=rhovs1(1:lx1,1:lx2,1:lx3,isp)
  paramtrim=ETD_uncoupled(paramtrim,Pr(:,:,:,isp),Lo(:,:,:,isp),dt)
  rhovs1(1:lx1,1:lx2,1:lx3,isp)=paramtrim

  vs1(:,:,:,isp)=rhovs1(:,:,:,isp)/(ms(isp)*max(ns(:,:,:,isp),mindensdiv))
end do

!ELECTRON VELOCITY SOLUTION
! in keeping with the way the above situations have been handled keep the ghost cells with this calculation
chrgflux = 0
do isp=1,lsp-1
  chrgflux=chrgflux+ns(:,:,:,isp)*qs(isp)*vs1(:,:,:,isp)
end do
!  vs1(1:lx1,1:lx2,1:lx3,lsp)=1/max(ns(1:lx1,1:lx2,1:lx3,lsp),mindensdiv)/qs(lsp)*(J1-chrgflux)   !density floor needed???
vs1(:,:,:,lsp)=-1/max(ns(:,:,:,lsp),mindensdiv)/qs(lsp)*chrgflux    !don't bother with FAC contribution...

!CLEAN VELOCITY
call clean_param(x,2,vs1)

if (mpi_cfg%myid==0 .and. debug) then
  call cpu_time(tfin)
  print *, 'Velocity sources substep for time step:  ',t,'done in cpu_time of:  ',tfin-tstart
end if


!ALL MASS SOURCES
call cpu_time(tstart)
call srcsContinuity(nn,vn1,vn2,vn3,Tn,ns,vs1,vs2,vs3,Ts,Pr,Lo)
Pr(:,:,:,1:6)=Pr(:,:,:,1:6)+Prprecip
do isp=1,lsp-1
  paramtrim=ns(1:lx1,1:lx2,1:lx3,isp)
  paramtrim=ETD_uncoupled(paramtrim,Pr(:,:,:,isp),Lo(:,:,:,isp),dt)
  ns(1:lx1,1:lx2,1:lx3,isp)=paramtrim    !should there be a density floor here???  I think so...
end do

if (mpi_cfg%myid==0 .and. debug) then
  call cpu_time(tfin)
  print *, 'Mass sources substep for time step:  ',t,'done in cpu_time of:  ',tfin-tstart
end if

!ELECTRON DENSITY SOLUTION
ns(:,:,:,lsp)=sum(ns(:,:,:,1:lsp-1),4)


!CLEAN DENSITY (CONSERVED VARIABLES WILL BE RECOMPUTED AT THE BEGINNING OF NEXT TIME STEP
call clean_param(x,1,ns)

!should the electron velocity be recomputed here now that densities have changed...

end subroutine fluid_adv


subroutine clean_param(x,paramflag,param)

!------------------------------------------------------------
!-------THIS SUBROUTINE ZEROS OUT ALL NULL CELLS AND HANDLES
!-------POSSIBLE NULL ARTIFACTS AT BOUNDARIES
!------------------------------------------------------------

class(curvmesh), intent(in) :: x
integer, intent(in) :: paramflag
real(wp), dimension(-1:,-1:,-1:,:), intent(inout) :: param     !note that this is 4D and is meant to include ghost cells

real(wp), dimension(-1:size(param,1)-2,-1:size(param,2)-2,-1:size(param,3)-2,lsp) :: paramnew
integer :: isp,ix1,ix2,ix3,iinull,ix1beg,ix1end

select case (paramflag)
  case (1)    !density
    param(:,:,:,1:lsp-1)=max(param(:,:,:,1:lsp-1),mindens)
    param(:,:,:,lsp)=sum(param(:,:,:,1:lsp-1),4)       !enforce charge neutrality based on ion densities

    do isp=1,lsp             !set null cells to some value
      if (isp==1) then
        do iinull=1,x%lnull
          ix1=x%inull(iinull,1)
          ix2=x%inull(iinull,2)
          ix3=x%inull(iinull,3)

          param(ix1,ix2,ix3,isp)=mindensnull*1e-2_wp
        end do
      else
        do iinull=1,x%lnull
          ix1=x%inull(iinull,1)
          ix2=x%inull(iinull,2)
          ix3=x%inull(iinull,3)

          param(ix1,ix2,ix3,isp)=mindensnull
        end do
      end if
    end do


    !SET DENSITY TO SOME HARMLESS VALUE in the ghost cells
    param(-1:0,:,:,:)=mindensdiv
    param(lx1+1:lx1+2,:,:,:)=mindensdiv
    param(:,-1:0,:,:)=mindensdiv
    param(:,lx2+1:lx2+2,:,:)=mindensdiv
    param(:,:,-1:0,:)=mindensdiv
    param(:,:,lx3+1:lx3+2,:)=mindensdiv
  case (2)    !velocity
    do isp=1,lsp       !set null cells to zero mometnum
      do iinull=1,x%lnull
        ix1=x%inull(iinull,1)
        ix2=x%inull(iinull,2)
        ix3=x%inull(iinull,3)

        param(ix1,ix2,ix3,isp) = 0
      end do
    end do

    !FORCE THE BORDER CELLS TO BE SAME AS THE FIRST INTERIOR CELL (deals with some issues on dipole grids), skip for non-dipole.
    if (x%gridflag==0) then      ! closed dipole
      do isp=1,lsp
        do ix3=1,lx3
          do ix2=1,lx2
            ix1beg=1
            do while( (.not. x%nullpts(ix1beg,ix2,ix3)) .and. ix1beg<lx1)     !find the first non-null index for this field line, need to be careful if no null points exist...
              ix1beg=ix1beg+1
            end do

            ix1end=ix1beg
            do while(x%nullpts(ix1end,ix2,ix3) .and. ix1end<lx1)     !find the first non-null index for this field line
              ix1end=ix1end+1
            end do

            if (ix1beg /= lx1) then    !only do this if we actually have null grid points
              param(ix1beg,ix2,ix3,isp)=param(ix1beg+1,ix2,ix3,isp)
            end if
            if (ix1end /= lx1) then
              param(ix1end,ix2,ix3,isp)=param(ix1end-1,ix2,ix3,isp)
            end if
          end do
        end do
      end do
    elseif (x%gridflag==1) then     ! open dipole grid, inverted
      do isp=1,lsp
        do ix3=1,lx3
          do ix2=1,lx2
            ix1end=1
            do while((.not. x%nullpts(ix1end,ix2,ix3)) .and. ix1end<lx1)     !find the first non-null index for this field line
              ix1end=ix1end+1
            end do

            if (ix1end /= lx1) then
              param(ix1end,ix2,ix3,isp)=param(ix1end-1,ix2,ix3,isp)
            end if
          end do
        end do
      end do
    end if

!MZ - for reasons I don't understand, this causes ctest to fail...  Generates segfaults everywhere in the CI (these are due to failing the comparisons)...  Okay so the deal here is that the ghost cell velocity values are used to compute artificial viscosity in fluid_adv, so one cannot clear them out without ruining the solution.  AFAIK no other params have this issue...
    !ZERO OUT THE GHOST CELL VELOCITIES
!    param(-1:0,:,:,:)= 0
!    param(lx1+1:lx1+2,:,:,:)= 0
!    param(:,-1:0,:,:)= 0
!    param(:,lx2+1:lx2+2,:,:)= 0
!    param(:,:,-1:0,:)= 0
!    param(:,:,lx3+1:lx3+2,:)= 0
  case (3)    !temperature
    param=max(param,100._wp)     !temperature floor

    do isp=1,lsp       !set null cells to some value
      do iinull=1,x%lnull
        ix1=x%inull(iinull,1)
        ix2=x%inull(iinull,2)
        ix3=x%inull(iinull,3)

        param(ix1,ix2,ix3,isp) = 100
      end do
    end do

    !> SET TEMPS TO SOME NOMINAL VALUE in the ghost cells
    param(-1:0,:,:,:) = 100
    param(lx1+1:lx1+2,:,:,:) = 100
    param(:,-1:0,:,:) = 100
    param(:,lx2+1:lx2+2,:,:) = 100
    param(:,:,-1:0,:) = 100
    param(:,:,lx3+1:lx3+2,:) = 100
  case default
    !! throw an error as the code is likely not going to behave in a predictable way in this situation...
    error stop '!non-standard parameter selected in clean_params, unreliable/incorrect results possible...'
end select

end subroutine clean_param

end module multifluid
