Name:           hello2
Version:        2.12.1
Release:        ${uuid}
Summary:        Prints a familiar, friendly greeting (variant)
License:        GPL-3.0-or-later AND GFDL-1.3-or-later
URL:            https://www.gnu.org/software/hello/
Source0:        https://ftp.gnu.org/gnu/hello/hello-%{version}.tar.gz

BuildRequires:  gcc
BuildRequires:  make
Recommends:     info
Provides:       bundled(gnulib)

%description
A variant build of the GNU Hello program for multi-component RPM release testing.
This package is built alongside hello to validate per-component architecture
targeting and noarch fanout behavior.


%package data
Summary:        Data files for hello2
BuildArch:      noarch

%description data
This package contains architecture-independent data files for hello2.


%prep
%setup -q -n hello-%{version}


%build
%configure
%make_build


%install
%make_install
rm -f %{buildroot}%{_infodir}/dir
%find_lang hello

mkdir -p %{buildroot}%{_datadir}/hello2
echo "hello2 data file" > %{buildroot}%{_datadir}/hello2/hello2.dat


%check
make check


%files -f hello.lang
%license COPYING
%{_mandir}/man1/hello.1*
%{_bindir}/hello
%{_infodir}/hello.info*


%files data
%{_datadir}/hello2/


%changelog
* Tue Apr 22 2026 Test User <test@example.com> - 2.12.1-1
- Initial hello2 package for multi-component RPM e2e testing
