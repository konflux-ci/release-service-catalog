#!/usr/bin/env bash
set -ex

# mocks to be injected into task step scripts

function kubectl() {
  # The IR won't actually be acted upon, so mock it to return Success as the task wants
  if [[ "$*" == "get internalrequest "*"-o=jsonpath={.status.results}" ]]
  then
    echo '{"result":"Success","advisory_url":"https://access.redhat.com/errata/RHBA-2025:1111"}'
  else
    /usr/bin/kubectl $*
  fi
}

function python3() {
  if [[ "$1" == "/home/utils/get_cgw_download_urls.py" ]]; then
    if [[ "$3" == "helm" ]]; then
      cat <<EOF
/content/origin/files/sha256/64/645cf4d7eeedac3983a3d6b0c30970fe6c6e1d5161a2af741d98352da6ec3435/sha256sum.txt
/content/origin/files/sha256/48/48c417949ed3324cd9e07f70665034b034e181be76c0d98c66be1701ba8dcefc/sha256sum.txt.gpg
/content/origin/files/sha256/4f/4f6b0af28e8193bfa8b48f93096abe6a11cbc97589d81b339ca7cc37b7f92d3c/sha256sum.txt.sig
/content/origin/files/sha256/c6/c6ff9aa942d710e73c877d765b7682bc22fcdbc59e43d708511ba21d249696c7/helm-linux-amd64
/content/origin/files/sha256/d3/d305ee5018571f2aca631da5faf4c87eb5ceced40ec59d134b7d2dd166b82bc6/helm-linux-amd64.tar.gz
/content/origin/files/sha256/68/682d2b002129ce26b33cce58c04a332d676f0b73913e4e9b07b430770b0fbfb3/helm-linux-arm64
/content/origin/files/sha256/79/79214155dddc843e33740e980a903bf960d69af30003a94869c312ae21b82c4e/helm-linux-arm64.tar.gz
/content/origin/files/sha256/bb/bbae88959ce1c212a98295e3444d74a048e6adcc69ef4d37673a8bf0cf383627/helm-linux-ppc64le
/content/origin/files/sha256/5a/5ae75a1fee696087a43f6704fb26bec0e3b4fdbdd5a3733526c976f997975cac/helm-linux-ppc64le.tar.gz
/content/origin/files/sha256/d4/d471c7386ae66d4624b2247d70a030adcedab47847dcf3b4fcf309511fd6a798/helm-linux-s390x
/content/origin/files/sha256/15/15d181a99a0d8a79727add99cf883a30b8deaf2526c4fb57f9d567d07e5c7b39/helm-linux-s390x.tar.gz
/content/origin/files/sha256/b2/b2bb962464ce206ad4b2afa9b5decd63b6a517cbe32fbb83c1b21ccb89c7b6df/helm-darwin-arm64
/content/origin/files/sha256/37/374ceeafa7c71a098f5985a2af4e33491fe0d532c8133e3e7a5e50ede35bf359/helm-darwin-arm64.tar.gz
/content/origin/files/sha256/6f/6f84bde5012e08b6ea46c39f3602793829d6dd62bc0639e76ce8c2c93c9c2345/helm-darwin-amd64
/content/origin/files/sha256/d6/d6d8ccfa84be20f8e3018c441e97f5459179d16e77a3c2996bf2c08559ad5832/helm-darwin-amd64.tar.gz
/content/origin/files/sha256/05/058c1052d82901c93d089f6ce261c0527067d5c3e2dd36776d2e67df68b10b7e/helm-windows-amd64.exe
/content/origin/files/sha256/38/38fb333e0c359824a451631e127247d0db44f1ac1de5b9b4d31bd5bb6ec9/helm-windows-amd64.exe.zip
EOF
    elif [[ "$3" == "odo" ]]; then
      cat <<EOF
/content/origin/files/sha256/31/31ac6ba34c1d807e7b282c305341ab03f9a4bd6559192b81334c393a1aee9d79/sha256sum.txt
/content/origin/files/sha256/ac/acc4ccfaed1deb346145c47c947da05dd656a89b43ef53fc12402d64dbdb5e85/sha256sum.txt.gpg
/content/origin/files/sha256/84/84108ebb0a74b46401511e00bf0a2e74a6bed6874000a44e4785d13c1cf2d048/sha256sum.txt.sig
/content/origin/files/sha256/5b/5ba537ab031969c7ab934f511400c1ab0bc5d3bd4714ddc5a1c84d03f1da62b1/odo-darwin-amd64
/content/origin/files/sha256/84/843a4845176f5b8f8d693a6138afaa893dd195ead6a1122cae437a71ec78b4cb/odo-darwin-amd64.tar.gz
/content/origin/files/sha256/25/258c981ca05894a4d3a4b9812939c3d78a4115ae9fcbefaeabeb6445005040c0/odo-darwin-arm64
/content/origin/files/sha256/68/68bc64b88474ca42d553f50f50ab28d7e0ddabca305ab9ee56c450558798f4b7/odo-darwin-arm64.tar.gz
/content/origin/files/sha256/c2/c271940c4b9d88f753423aae78984b7ef7a99ac9133154714b679f8b8b3bec8e/odo-linux-amd64
/content/origin/files/sha256/e5/e539bb37a2084d381562ed8808f3dca3dc918e1c4917d94e5357f2e97185b415/odo-linux-amd64.tar.gz
/content/origin/files/sha256/52/52236760344ec54724c65567832e1473d28afef65276826531435947457ac375/odo-linux-arm64
/content/origin/files/sha256/0f/0fa32171f48a3856c38bec4ffd923b2dd9be18f07e1380c303615ac8a830d363/odo-linux-arm64.tar.gz
/content/origin/files/sha256/1d/1dccd03466e2fabc981585fb5efb6f84d18ecf53f0350ec4e1d5c67ff88e5aa1/odo-linux-ppc64le
/content/origin/files/sha256/be/bee804564395d0830034ac33b327c7a2f8a7b5b9bccf9fb3b399890b728d7a3e/odo-linux-ppc64le.tar.gz
/content/origin/files/sha256/1d/1d70e9777cd10ba280d4c04d7fe69bf1a86e1901c135c7592ee189291716e8c8/odo-linux-s390x
/content/origin/files/sha256/e9/e9e44c7a2c086662dc0907207faee0589b6c84c79a270700f488577d180379c8/odo-linux-s390x.tar.gz
/content/origin/files/sha256/e1/e147d6d9c9940389790084fcbff749600dbeafd5f4495320ba1a09ea0ddcef3c/odo-windows-amd64.exe
/content/origin/files/sha256/04/04b0a14eb0ef13c0d8ac862cd2abeea9de74e26624c6d38fc6bc8a5759a8f9e8/odo-windows-amd64.exe.zip
EOF
    elif [[ "$3" == "RHELAI" ]]; then
      dir1="/content/origin/files/sha256/ae/aea86cd520f01d3b9c488fe11de9a6241c825018ff834cebce8d988046a1a8ac"
      file1="rhel-ai-intel-1.5.1-1749643937-x86_64.iso.gz"
      echo "$dir1/$file1"
      dir2="/content/origin/files/sha256/f7/f7dc49d369465abebb6aebf60a9962f49af854a4960d61ff6aa1f02325cee26d"
      file2="rhel-ai-intel-1.5.1-1749643939-x86_64-kvm.qcow2"
      echo "$dir2/$file2"
    else
      echo "Unknown product: $3" >&2
      return 1
    fi
  else
    /usr/bin/python3 "$@"
  fi
}
