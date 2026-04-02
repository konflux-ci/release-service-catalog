Name:           hello
Version:        2.12.1
Release:        ${uuid}
Summary:        Prints a familiar, friendly greeting
# All code is GPLv3+.
# Parts of the documentation are under GFDL
License:        GPL-3.0-or-later AND GFDL-1.3-or-later
URL:            https://www.gnu.org/software/hello/
Source0:        https://ftp.gnu.org/gnu/hello/hello-%{version}.tar.gz
Source1:        https://ftp.gnu.org/gnu/hello/hello-%{version}.tar.gz.sig
Source2:        https://ftp.gnu.org/gnu/gnu-keyring.gpg

BuildRequires:  gcc
BuildRequires:  gnupg2
BuildRequires:  make
Recommends:     info
Provides:       bundled(gnulib)

%description
The GNU Hello program produces a familiar, friendly greeting.
Yes, this is another implementation of the classic program that
prints “Hello, world!” when you run it.

However, unlike the minimal version often seen, GNU Hello processes
its argument list to modify its behavior, supports greetings in many
languages, and so on. The primary purpose of GNU Hello is to
demonstrate how to write other programs that do these things; it
serves as a model for GNU coding standards and GNU maintainer
practices.


%package data
Summary:        Data files for GNU Hello
BuildArch:      noarch

%description data
This package contains architecture-independent data files for GNU Hello.


%prep
%{gpgverify} --keyring='%{SOURCE2}' --signature='%{SOURCE1}' --data='%{SOURCE0}'
%setup -q


%build
%configure
%make_build


%install
%make_install
rm -f %{buildroot}%{_infodir}/dir
%find_lang hello

mkdir -p %{buildroot}%{_datadir}/hello
echo "GNU Hello data file" > %{buildroot}%{_datadir}/hello/hello.dat


%check
make check


%files -f hello.lang
%license COPYING
%{_mandir}/man1/hello.1*
%{_bindir}/hello
%{_infodir}/hello.info*


%files data
%{_datadir}/hello/


%changelog
* Tue Mar 10 2026 Test User <test@example.com> - 2.12.1-7
- Add hello-data noarch subpackage for e2e testing

* Fri Jan 17 2025 Fedora Release Engineering <releng@fedoraproject.org> - 2.12.1-6
- Rebuilt for https://fedoraproject.org/wiki/Fedora_42_Mass_Rebuild

* Thu Jul 18 2024 Fedora Release Engineering <releng@fedoraproject.org> - 2.12.1-5
- Rebuilt for https://fedoraproject.org/wiki/Fedora_41_Mass_Rebuild

* Wed Jan 24 2024 Fedora Release Engineering <releng@fedoraproject.org> - 2.12.1-4
- Rebuilt for https://fedoraproject.org/wiki/Fedora_40_Mass_Rebuild

* Sat Jan 20 2024 Fedora Release Engineering <releng@fedoraproject.org> - 2.12.1-3
- Rebuilt for https://fedoraproject.org/wiki/Fedora_40_Mass_Rebuild

* Thu Jul 20 2023 Fedora Release Engineering <releng@fedoraproject.org> - 2.12.1-2
- Rebuilt for https://fedoraproject.org/wiki/Fedora_39_Mass_Rebuild

* Tue Jul  4 2023 Jens Petersen <petersen@redhat.com> - 2.12.1-1
- update to 2.12.1
- SPDX migration of license tags

* Thu Jan 19 2023 Fedora Release Engineering <releng@fedoraproject.org> - 2.10-9
- Rebuilt for https://fedoraproject.org/wiki/Fedora_38_Mass_Rebuild

* Thu Jul 21 2022 Fedora Release Engineering <releng@fedoraproject.org> - 2.10-8
- Rebuilt for https://fedoraproject.org/wiki/Fedora_37_Mass_Rebuild

* Thu Jan 20 2022 Fedora Release Engineering <releng@fedoraproject.org> - 2.10-7
- Rebuilt for https://fedoraproject.org/wiki/Fedora_36_Mass_Rebuild

* Thu Jul 22 2021 Fedora Release Engineering <releng@fedoraproject.org> - 2.10-6
- Rebuilt for https://fedoraproject.org/wiki/Fedora_35_Mass_Rebuild

* Tue Jan 26 2021 Fedora Release Engineering <releng@fedoraproject.org> - 2.10-5
- Rebuilt for https://fedoraproject.org/wiki/Fedora_34_Mass_Rebuild

* Tue Jul 28 2020 Fedora Release Engineering <releng@fedoraproject.org> - 2.10-4
- Rebuilt for https://fedoraproject.org/wiki/Fedora_33_Mass_Rebuild

* Wed Apr  1 2020 Jens Petersen <petersen@redhat.com> - 2.10-3
- packaging fixes (#1810897)
- use https urls
- use make_build, make_install, buildroot, and license macros

* Fri Mar  6 2020 Jens Petersen <petersen@redhat.com> - 2.10-2
- add gpgverify of source

* Thu Mar  5 2020 Jens Petersen <petersen@redhat.com> - 2.10-1
- update to 2.10

* Fri Jan 13 2012 Fedora Release Engineering <rel-eng@lists.fedoraproject.org> - 2.6-3
- Rebuilt for https://fedoraproject.org/wiki/Fedora_17_Mass_Rebuild

* Wed Feb 09 2011 Fedora Release Engineering <rel-eng@lists.fedoraproject.org> - 2.6-2
- Rebuilt for https://fedoraproject.org/wiki/Fedora_15_Mass_Rebuild

* Wed Jan 12 2011 Conrad Meyer <konrad@tylerc.org> - 2.6-1
- Bump to 2.6.

* Sun Mar 28 2010 Conrad Meyer <konrad@tylerc.org> - 2.5-1
- Bump version.

* Fri Jul 24 2009 Fedora Release Engineering <rel-eng@lists.fedoraproject.org> - 2.4-3
- Rebuilt for https://fedoraproject.org/wiki/Fedora_12_Mass_Rebuild

* Tue Feb 24 2009 Fedora Release Engineering <rel-eng@lists.fedoraproject.org> - 2.4-2
- Rebuilt for https://fedoraproject.org/wiki/Fedora_11_Mass_Rebuild

* Wed Dec 17 2008 Conrad Meyer <konrad@tylerc.org> - 2.4-1
- Initial package.
