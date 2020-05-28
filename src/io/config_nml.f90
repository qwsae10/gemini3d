submodule(config) config_nml

implicit none (type, external)

contains


module procedure read_nml

integer :: u, i

integer :: ymd(3)
real(wp) :: UTsec0
real(wp) :: tdur
real(wp) :: dtout
real(wp) :: activ(3)
real(wp) :: tcfl
real(wp) :: Teinf
integer :: potsolve, flagperiodic=0, flagoutput, flagcap=0
integer :: interptype
real(wp) :: sourcemlat,sourcemlon
real(wp) :: dtneu
real(wp) :: dxn,drhon,dzn
real(wp) :: dtprec=0
character(256) :: indat_size, indat_grid, indat_file, source_dir, prec_dir, E0_dir
character(4) :: file_format=""  !< need to initialize blank or random invisible fouls len_trim>0
real(wp) :: dtE0=0
integer :: flagdneu, flagprecfile, flagE0file, flagglow !< FIXME: these four parameters are ignored, kept temporarily
real(wp) :: dtglow=0, dtglowout=0
character(:), allocatable :: compiler_vendor

namelist /base/ ymd, UTsec0, tdur, dtout, activ, tcfl, Teinf
namelist /files/ file_format, indat_size, indat_grid, indat_file
namelist /flags/ potsolve, flagperiodic, flagoutput, flagcap, &
   flagdneu, flagprecfile, flagE0file, flagglow !< FIXME: these last four parameters are ignored, kept temporarily for compatibility, should be removed
namelist /neutral_perturb/ interptype, sourcemlat, sourcemlon, dtneu, dxn, drhon, dzn, source_dir
namelist /precip/ dtprec, prec_dir
namelist /efield/ dtE0, E0_dir
namelist /glow/ dtglow, dtglowout


compiler_vendor = get_compiler_vendor()

open(newunit=u, file=cfg%infile, status='old', action='read')

read(u, nml=base, iostat=i)
call check_nml_io(i, cfg%infile, "base", compiler_vendor)
cfg%ymd = ymd
cfg%UTsec0 = UTsec0
cfg%tdur = tdur
cfg%dtout = dtout
cfg%activ = activ
cfg%tcfl = tcfl
cfg%Teinf = Teinf

rewind(u)
read(u, nml=flags, iostat=i)
call check_nml_io(i, cfg%infile, "flags", compiler_vendor)
cfg%potsolve = potsolve
cfg%flagperiodic = flagperiodic
cfg%flagoutput = flagoutput
cfg%flagcap = flagcap

rewind(u)
read(u, nml=files, iostat=i)
call check_nml_io(i, cfg%infile, "files", compiler_vendor)

!> auto file_format if not specified
if (len_trim(file_format) > 0) then
  cfg%out_format = trim(file_format)
else
  file_format = get_suffix(indat_size)
  cfg%out_format = file_format(2:)
endif

cfg%indatsize = expanduser(indat_size)
cfg%indatgrid = expanduser(indat_grid)
cfg%indatfile = expanduser(indat_file)

if (namelist_exists(u, "neutral_perturb", verbose)) then
  cfg%flagdneu = 1
  read(u, nml=neutral_perturb, iostat=i)
  call check_nml_io(i, cfg%infile, "neutral_perturb", compiler_vendor)
  cfg%sourcedir = expanduser(source_dir)
  cfg%interptype = interptype
  cfg%sourcemlat = sourcemlat
  cfg%sourcemlon = sourcemlon
  cfg%dtneu = dtneu
  cfg%drhon = drhon
  cfg%dzn = dzn
  cfg%dxn = dxn
else
  cfg%flagdneu = 0
  cfg%sourcedir = ""
endif

if (namelist_exists(u, "precip", verbose)) then
  cfg%flagprecfile = 1
  read(u, nml=precip, iostat=i)
  call check_nml_io(i, cfg%infile, "precip", compiler_vendor)
  cfg%precdir = expanduser(prec_dir)
  cfg%dtprec = dtprec
else
  cfg%flagprecfile = 0
  cfg%precdir = ""
endif

if (namelist_exists(u, "efield", verbose)) then
  cfg%flagE0file = 1
  read(u, nml=efield, iostat=i)
  call check_nml_io(i, cfg%infile, "efield", compiler_vendor)
  cfg%E0dir = expanduser(E0_dir)
  cfg%dtE0 = dtE0
else
  cfg%flagE0file = 0
  cfg%E0dir = ""
endif

if (namelist_exists(u, "glow", verbose)) then
  cfg%flagglow = 1
  read(u, nml=glow, iostat=i)
  call check_nml_io(i, cfg%infile, "glow", compiler_vendor)
  cfg%dtglow = dtglow
  cfg%dtglowout = dtglowout
else
  cfg%flagglow = 0
endif

close(u)

end procedure read_nml


logical function namelist_exists(u, nml, verbose)
!! determines if Namelist exists in file

character(*), intent(in) :: nml
integer, intent(in) :: u
logical, intent(in), optional :: verbose

logical :: debug
integer :: i
character(256) :: line  !< arbitrary length

debug = .false.
if(present(verbose)) debug = verbose

namelist_exists = .false.

rewind(u)

do
  read(u, '(A)', iostat=i) line
  if(i/=0) exit
  if (line(1:1) /= '&') cycle
  if (line(2:) == nml) then
    namelist_exists = .true.
    exit
  end if
end do
rewind(u)

if (debug) print *, 'namelist ', nml, namelist_exists

end function namelist_exists


subroutine check_nml_io(i, filename, namelist, vendor)
!! checks for EOF and gives helpful error
!! this accomodates non-Fortran 2018 error stop with variable character

integer, intent(in) :: i
character(*), intent(in) :: filename
character(*), intent(in), optional :: namelist, vendor

character(:), allocatable :: nml, msg

if(i==0) return

nml = ""
if(present(namelist)) nml = namelist

if (is_iostat_end(i)) then
  write(stderr,*) 'ERROR: namelist ' // nml // ': ensure there is a trailing blank line in ' // filename
  error stop 5
endif

msg = ""
if (present(vendor)) then
  select case (vendor)
  case ("Intel")
    !! https://software.intel.com/en-us/fortran-compiler-developer-guide-and-reference-list-of-run-time-error-messages
    select case (i)
    case (19)
      msg = "mismatch between variable names in namelist and Fortran code, or problem in variable specification in file"
    case (623)
      msg = "variable specified in Fortran code missing from Namelist file"
    case (17,18,624,625,626,627,628,680,750,759)
      msg = "namelist file format problem"
    end select
  case ("GCC", "GNU")
    select case (i)
    case (5010)
      msg = "mismatch between variable names in namelist and Fortran code, or problem in variable specification in file"
    end select
  end select
endif

if (len(msg)==0) write(stderr,*) "namelist read error code",i

write(stderr,'(A,/,A)') 'ERROR: reading namelist ', nml, " from ", filename, " problem: ", msg
error stop 5

end subroutine check_nml_io

end submodule config_nml