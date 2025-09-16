
# Creating Pulp Resources

## setup
* obtain the value of the field `cli.toml` from the pulp secret in the managed secret yaml.
* copy contents of field `cli.toml` to ~/.config/pulp/cli.toml
## create
```
$ ./create-pulp-resources.sh konflux-release-integration-tests "source,x86_64,s390x,ppc64le,aarch64"
```
