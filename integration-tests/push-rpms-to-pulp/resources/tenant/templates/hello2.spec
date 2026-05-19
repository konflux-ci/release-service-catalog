Name:           hello2
Version:        2.12.1
Release:        ${uuid}
Summary:        Noarch-only test component for RPM release E2E
License:        GPL-3.0-or-later
URL:            https://www.gnu.org/software/hello/
Source0:        https://ftp.gnu.org/gnu/hello/hello-%{version}.tar.gz

BuildArch:      noarch

%description
Produces only noarch and source RPMs (no arch-specific binaries). Used to validate
that push-rpms-to-pulp falls back to DEFAULT_ARCHITECTURES and fans out noarch RPMs
to every default binary arch repo.


%prep
# Tarball unpacks as hello-%{version}/ (package-name=hello); Name is hello2.
%setup -q -n hello-%{version}


%build
# Data-only package; no compilation required.


%install
mkdir -p %{buildroot}%{_datadir}/hello2
echo "hello2 noarch-only data" > %{buildroot}%{_datadir}/hello2/hello2.dat


%files
%{_datadir}/hello2/


%changelog
* Tue May 19 2026 Test User <test@example.com> - 2.12.1-2
- Noarch-only package: only *.noarch.rpm and *.src.rpm (no arch-specific binaries)

* Tue Apr 22 2026 Test User <test@example.com> - 2.12.1-1
- Initial hello2 package for multi-component RPM e2e testing
