module spherical

!> utility routines to compute various quantities relevant to spherical coordiante systems
use phys_consts, only: wp
implicit none (type, external)

contains

!> radial unit vector (expressed in ECEF cartesian coodinates, components permuted as ix,iy,iz)
function calc_er_spher(theta,phi) result(er)
  real(wp), dimension(:,:,:), intent(in) :: theta,phi
  real(wp), dimension(1:size(theta,1),1:size(theta,2),1:size(theta,3),3) :: er

  ! fixme: error checking

  er(:,:,:,1)=sin(theta)*cos(phi)
  er(:,:,:,2)=sin(theta)*sin(phi)
  er(:,:,:,3)=cos(theta)
end function calc_er_spher


!> zenith angle unit vector (expressed in ECEF cartesian coodinates
subroutine calc_etheta_spher(theta,phi) result(etheta)
  real(wp), dimension(:,:,:), intent(in) :: theta,phi
  real(wp), dimension(1:size(theta,1),1:size(theta,2),1:size(theta,3),3) :: etheta

  ! fixme: error checking

  etheta(:,:,:,1)=cos(theta)*cos(phi)
  etheta(:,:,:,2)=cos(theta)*sin(phi)
  etheta(:,:,:,3)=-sin(theta)
end subroutine calc_etheta_spher

!> azimuth angle unit vector (ECEF cart.)
subroutine calc_ephi_spher(theta,phi) result(ephi)
  real(wp), dimension(:,:,:), intent(in) :: theta,phi
  real(wp), dimension(1:size(theta,1),1:size(theta,2),1:size(theta,3),3) :: etheta

  ! fixme: error checking

  ephi(:,:,:,1)=-sin(phi)
  ephi(:,:,:,2)=cos(phi)
  ephi(:,:,:,3)=0
end subroutine calc_ephi_spher

end module spherical
