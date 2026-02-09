#!/bin/bash
set -euo pipefail

# Script to generate a pool of 200 different container images for large snapshot testing
# 
# CRITICAL: Even immutable digests can have MUTABLE SBOM attachments!
# This script validates SBOM format at RUNTIME for maximum test stability.

TARGET_COUNT="${1:-200}"
OUTPUT_FILE="${2:-/tmp/image-pool.txt}"

echo "🔍 Generating pool of ${TARGET_COUNT} different container images" >&2
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2

# ============================================================================
# CANDIDATE DIGEST POOL
# ============================================================================
# Previously verified with SPDX SBOMs, but attachments can be overwritten.
# Runtime validation ensures current SBOM format is SPDX.
# ============================================================================
CANDIDATE_DIGESTS=(
    "quay.io/konflux-ci/image-controller@sha256:d24929e4fbe0bfbf65688f203372e7de4cc0b9336e8e271a47a1865088dbc5c0"
    "quay.io/konflux-ci/image-controller@sha256:be6d27cf2333f2b28748c08b0e653bf74b3886400ac879fb512b9411e4e2ac97"
    "quay.io/konflux-ci/image-controller@sha256:244676eff9eb6ca0792c7f5c03f1ed683ff5e6e9e340d65caa589817ba8e5609"
    "quay.io/konflux-ci/image-controller@sha256:f3fc43b8d023350ffd70ae7bea77cd4c4a323b27ada2cf49f4da99cad3cc6133"
    "quay.io/konflux-ci/image-controller@sha256:0bd024096d63e6f1ae3d122bfdc0c5a131369ed37f514f42b86760f6ce9c7ffc"
    "quay.io/konflux-ci/image-controller@sha256:79504601a5669782c93d3406726527600d57071d8209e7b40464069d21884f8b"
    "quay.io/konflux-ci/image-controller@sha256:6db3a8d9ba832ab5af381e209b8321ba2fbd1402eddc67bf07e158a0837b7c99"
    "quay.io/konflux-ci/image-controller@sha256:43d74c2cae8d286e5019c92238bcce6ab54b55eaedbecf9671a3ae9b2deb1e4e"
    "quay.io/konflux-ci/image-controller@sha256:88d46ad6564659c1d2fc4298bdcff40d3d6353b96ad8abce473d33c6dbc98a76"
    "quay.io/konflux-ci/image-controller@sha256:b798f25a5d0908ff56ed94962b3502c410b9f6a51fa43076f94c0e2f2c1d2e16"
    "quay.io/konflux-ci/image-controller@sha256:2d5cfeb85a56f8f37b76cf9d17bdbefe4b1f98ba44eb672745d9076017e3f815"
    "quay.io/konflux-ci/image-controller@sha256:3756a754a9465e11afac55a4aae9c0ac9e64eb885c6fb905cc32b7bad62900e3"
    "quay.io/konflux-ci/image-controller@sha256:784f55370782fdced86e82ee74680871558ec7b8ce6de03108f9124927e78c13"
    "quay.io/konflux-ci/image-controller@sha256:58eeaf920a69d1ec396c854387ef0abec956ccee09bdf137355021b65a1ee383"
    "quay.io/konflux-ci/image-controller@sha256:5f648dff17b2ce5aea23e3c72e64d74b6973df77356afa17efed9da0aa7ec137"
    "quay.io/konflux-ci/image-controller@sha256:abf64a4750b321228d24067bd560ed231be20aee8e8f5ed71a525f68e2687e3b"
    "quay.io/konflux-ci/image-controller@sha256:3bdce3683d6c02ba71eebb1ad64a3d9408a0b99885a3c8f8d4e6554f8b32757e"
    "quay.io/konflux-ci/image-controller@sha256:3b3064ea345711b6877cea5c5653c582745eb98b2815d58bf08b35c3fefa5d79"
    "quay.io/konflux-ci/image-controller@sha256:fdda3e9e39c907c5ff393819d286feade9bb4400074e54066b6faf17fbdafafb"
    "quay.io/konflux-ci/image-controller@sha256:ea0eb52ee95007725166e238e1996adb38946513ccb0f35ce3d0b97281c394f6"
    "quay.io/konflux-ci/image-controller@sha256:7742e85c0b9925ab77993f9872664cef50fbd7356d2604ea5e07287b6b0233c3"
    "quay.io/konflux-ci/image-controller@sha256:df904222fc295fe7bbd247bccb9800706f812e57b50f01eb16e2441d6e5757dc"
    "quay.io/konflux-ci/image-controller@sha256:2a4640c6a9aa141b12423a9abc658d0071ae5767ed179044957ddd604e566dae"
    "quay.io/konflux-ci/image-controller@sha256:d578c7b899d3cf74bac2a65d16fa9e3cd1136227a87924c415899a65354e25dc"
    "quay.io/konflux-ci/image-controller@sha256:4fe3f13759468807520ea0ff46246c33a8a75e528ea584b53c3e0405d1171079"
    "quay.io/konflux-ci/image-controller@sha256:320bec686cbff6bc715eb247b9839ab7fccb08ab6b5c8e2185cb79b2c9775b4e"
    "quay.io/konflux-ci/image-controller@sha256:fbdcdca72fd5eac865d3790e259632f427e8568347a9fd97a7c0af2d0b5547c1"
    "quay.io/konflux-ci/image-controller@sha256:29ee6cbffb3bbbc3d50f6c036c2b451d91c9e6a7cb00f8db9e71d0ba3e039fe7"
    "quay.io/konflux-ci/image-controller@sha256:eb253bc634f3d1feea76e856c2c6a389db69a5a4e171e77ec192d303d94f7f35"
    "quay.io/konflux-ci/image-controller@sha256:4b0f05ffa5b9544333a2a57798d2f10b5f521204dd8ca797f2e05a4d902ca875"
    "quay.io/konflux-ci/image-controller@sha256:95d625bb6c9729dfb2d13e14e282c1a4e982c399f068516c6e852c1e4556edc1"
    "quay.io/konflux-ci/image-controller@sha256:dad6e3081cdc3a6302beac0d5c9163f10cf96b48192a6f611d6422ae63a7e0bd"
    "quay.io/konflux-ci/image-controller@sha256:2ecafeeb3ba56b82d627ec732d35ceb8ed5ed117e973f2f787de587460532ffd"
    "quay.io/konflux-ci/image-controller@sha256:ea521aeee1fb42ac5590613575346dfedabdf2e4dfdb078774ee3f2bd616a2c3"
    "quay.io/konflux-ci/image-controller@sha256:537e39dfe373d15af613ef9fd304c9da3e637cdb0de6507051a9e9070a3d7ef7"
    "quay.io/konflux-ci/image-controller@sha256:6da6d8f940c54c65d794f13215f7d45238a73d104e35f52809d8066ccf1e6f43"
    "quay.io/konflux-ci/image-controller@sha256:6f005a3154e4d6381b564eba0971fc3a75eb11a810b6936d42a65168524ea9a4"
    "quay.io/konflux-ci/image-controller@sha256:cbd958a3a29e3f8bd37cc623af116e338594d7b5355d1d03197137b116bad721"
    "quay.io/konflux-ci/image-controller@sha256:f113f4a5d7fdbfc2eced7215e7da16001ada04632e68ad7570aa1446747a1f3a"
    "quay.io/konflux-ci/image-controller@sha256:05fe6432d001f388a6ae834ba55a9e8b4f85a0ded556f2a3958c0b38e6f73206"
    "quay.io/konflux-ci/image-controller@sha256:94587bae85ad3b92432c19974eea85e4544f2415e8c3df88d00cfda26265e5d1"
    "quay.io/konflux-ci/image-controller@sha256:bdeba1a1f53856c80662eb160b626e7f49ed36c35132374636e9c29a30a29a0a"
    "quay.io/konflux-ci/image-controller@sha256:be21c46bf7ace04659eaee6f33ac72647f0aa7aa693bf59e0191cd6e52ce756f"
    "quay.io/konflux-ci/image-controller@sha256:b4c1a49ba82fa293b027265c8c53b1e4db55d19064c3d26a7b1e54921475a398"
    "quay.io/konflux-ci/mintmaker@sha256:077f8c7ea58a751c77842c326260fa52647e9bb2f08bb0697c592cccbbe7d736"
    "quay.io/konflux-ci/mintmaker@sha256:02b4c6fdeebc630ee3872743e81b7727be5c825285aa1d205fcfb5b76f23dfe1"
    "quay.io/konflux-ci/mintmaker@sha256:3831d448a93e44f5199250264dbe7a8d1cd2705993619d7f318b924d9c40815e"
    "quay.io/konflux-ci/mintmaker@sha256:95d875065c66776ef144ed2c4a1eaa7539ee6e0a959be7ccfb14cbc3c1354fc1"
    "quay.io/konflux-ci/mintmaker@sha256:1f737023ae90a8c94c1027481698d4c4b8ddbf3790574766c514cd3e1309b303"
    "quay.io/konflux-ci/mintmaker@sha256:a1755350837337cbb372a25845fcdd1741e10137994de5849320bdf4d2877ba6"
    "quay.io/konflux-ci/mintmaker@sha256:ea7e7651a6ad4f7d99865dde74775b0de3d819d3b19c7d287757db3c6a32da4a"
    "quay.io/konflux-ci/mintmaker@sha256:6e56ebe376a14126598e5daa1c7227424e510b2382ba88145c5236e91e9f84ea"
    "quay.io/konflux-ci/mintmaker@sha256:cd67ef85725cd7fedbc77862974bca073103c3b55cd9b728b142a5356cdbdd6b"
    "quay.io/konflux-ci/mintmaker@sha256:58c2a44463ed50620c2a8eeaa014942d9a764d30555c808ae1f2d195a1a2d09f"
    "quay.io/konflux-ci/mintmaker@sha256:dd6ec57f7c3b8741cb36f4046785833305cf45a63164cf19a038603fe7281348"
    "quay.io/konflux-ci/mintmaker@sha256:909ebe2a2f4b7aed8494822b3828e3065843fee0b6165e39cdbd7d2dce4bafc1"
    "quay.io/konflux-ci/mintmaker@sha256:1d6e680a45e289b3d2757a9ffe209a2df91cc2bae7789ec6827414d8d4c1b3a6"
    "quay.io/konflux-ci/mintmaker@sha256:7c275625922b681c333e1fa4950a605821b8e55503e3fb0d86176000f7e85a38"
    "quay.io/konflux-ci/mintmaker@sha256:7d5069f280db74968778e236939ce2d6849f7c869e171e07d5a3a1b3c24c4f38"
    "quay.io/konflux-ci/mintmaker@sha256:741f870d31cd3b1c6d618081dfd65275ae64d28d7b5355a13d9fc78a787eac30"
    "quay.io/konflux-ci/mintmaker@sha256:f69c2bdd142c44be2aabf942c129ef4f3b8ff54aa0203cc31c97b151c5cd0ae8"
    "quay.io/konflux-ci/mintmaker@sha256:633ca8d8e9254d068867a990d10a61e0a88bafffe9e05a0c31cb95855f1289ca"
    "quay.io/konflux-ci/mintmaker@sha256:d5458462fc5c54a0175b6f121f71292a59b15c3785ae6960a1d1ba87af1b8e87"
    "quay.io/konflux-ci/mintmaker@sha256:e74bb6f5fb47740df6665d61cb8b9281a0185b5a048b492e00a42fc6b01fe238"
    "quay.io/konflux-ci/multi-platform-controller@sha256:f8c8b7be224496d1b73170215b2ec1daecc3c517fc681d78c588ab70a913b4b3"
    "quay.io/konflux-ci/multi-platform-controller@sha256:fc653f72645c3c1f5d28251c3bb34133c1db0ac575230a510cba2a0378be304f"
    "quay.io/konflux-ci/multi-platform-controller@sha256:8d2110263cf223c4f543051eff50985029f3edc9cc5d701bdd3262c6b3fc53d5"
    "quay.io/konflux-ci/multi-platform-controller@sha256:ddaa6e940489a3b90e6a1b4e3dc7435fc0abe0ce6d10e65b9e4638fbb11ec938"
    "quay.io/konflux-ci/multi-platform-controller@sha256:1e01e69ba16ef2984eeaff76891b9e2744829880bb647265058f9bd0d25d668f"
    "quay.io/konflux-ci/multi-platform-controller@sha256:fa983c73b858c028196bdf5625c6a6b77f9484696773f724627b23cc9a4924a0"
    "quay.io/konflux-ci/multi-platform-controller@sha256:ee9782726da8787feaa6566fbd0dc65ccb91e81e43303792dfccb10969ed7f4e"
    "quay.io/konflux-ci/multi-platform-controller@sha256:fa48727e353b4b5b01a168ea26afe018cdf9937e3d15f7cff57c35e2074c4d64"
    "quay.io/konflux-ci/multi-platform-controller@sha256:2e3151999d382ea5ff2a7c4cdf5305b10bc2618cbabb0719d6334c9bde39f3e3"
    "quay.io/konflux-ci/multi-platform-controller@sha256:f0bd37ca46e52b453820ab31bd7ddd4c1d32da8adb3fd4b6397b0a6493d6e25a"
    "quay.io/konflux-ci/multi-platform-controller@sha256:7c5432e6ed2ec33c2431a6775e2c1ea66a2dcb5c6519702890234e65df105289"
    "quay.io/konflux-ci/multi-platform-controller@sha256:0f154b8df4bc1dabc7d7d17986a309270c6a1e7c632454818ece28a21e69bca0"
    "quay.io/konflux-ci/multi-platform-controller@sha256:df6c7baebf97ad2aec3bd319db90a1fbb8044e58cbc7e061e647bbe186a6d880"
    "quay.io/konflux-ci/multi-platform-controller@sha256:90eb7c4e5c4873f91bbe139fa2f1261e62e77b22d4884c20cdb818b4451a6b37"
    "quay.io/konflux-ci/multi-platform-controller@sha256:07f16ecb323e19552b3980c7cac25b803a3673d2f4dde85f6967d2f4e36214dd"
    "quay.io/konflux-ci/multi-platform-controller@sha256:746482d38b9ec9d30642cd4511da3f93d65aa5052d10e6038b964cc61e9c1471"
    "quay.io/konflux-ci/multi-platform-controller@sha256:d09e840b48e96e68cc89a2f90caf2d4941635e16e53f0cee22c8e297a40e99b4"
    "quay.io/konflux-ci/multi-platform-controller@sha256:2dd442a6c5d95e8b93c61dbc4d8170360b553981ec1645b6fa160db0a505e87c"
    "quay.io/konflux-ci/multi-platform-controller@sha256:9961b0c1006ad1aca3e75493202999b545d05547782a37dee5c7e88e0a37cef9"
    "quay.io/konflux-ci/multi-platform-controller@sha256:abbaf404d0760f65e2f3ede34e07842f2bc0d2d3fa60e25d13197a55a3e31830"
    "quay.io/konflux-ci/multi-platform-controller@sha256:88227a694a4ab9cd7efbfc5e5a3ed250c680aa4d4925b8265402cab38c3a7cbb"
    "quay.io/konflux-ci/multi-platform-controller@sha256:19907635c013ce99b4ea404b630f4215823fc4104c9149e25baf9514ea5ea0c2"
    "quay.io/konflux-ci/multi-platform-controller@sha256:605ac25831291e914b096fa88376c50c9f4c9648331a847fb20cec3399ab8f3b"
    "quay.io/konflux-ci/multi-platform-controller@sha256:65152abe54bc4694625ba5e2dbc3163b4066fe8b1e47601254271a8fd169bd41"
    "quay.io/konflux-ci/multi-platform-controller@sha256:0ed0389eb86f5a0ae2cdd619d0671efa1c17f5f8bde0770b17398ed98d0c5a06"
    "quay.io/konflux-ci/multi-platform-controller@sha256:d215ba7aa88ab84349d62ccc3e893ba0f1f8954fe795990873afff5bbdd51e2a"
    "quay.io/konflux-ci/multi-platform-controller@sha256:9421a7adc15cd4ac5f154aeff761387834bcb759e659bad282650955e43d1cdc"
    "quay.io/konflux-ci/multi-platform-controller@sha256:11842b3f55e770ba4f4ced939c1f4defe2b6509a4877e3a1e6898c4a1d14ec0b"
    "quay.io/konflux-ci/multi-platform-controller@sha256:567295889d9a0f31a3d6bda94288e83a5c93586fb76d598cd4cef1ae3c4b2e73"
    "quay.io/konflux-ci/multi-platform-controller@sha256:92d34b94c6d27e2a26023737115a0912730e05e28e42aa8d5e4d3105f28cfaa9"
    "quay.io/konflux-ci/multi-platform-controller@sha256:37789ecbbe14e8fd2cedca2e05dd5b09db01d518cf370b0649549e869e1b662f"
    "quay.io/konflux-ci/multi-platform-controller@sha256:35a1314a13e2d13965a7ef6746055a0dc23b54513c22759563c03539ffe2c3bf"
    "quay.io/konflux-ci/multi-platform-controller@sha256:89db3d91d9070c1e25a06291ff43e4fea044296957c6e38f1f06c73595c543de"
    "quay.io/konflux-ci/multi-platform-controller@sha256:67c9221e1629518ce26eface6e655309e832dbbf15066fada1c2aa01806fe606"
    "quay.io/konflux-ci/multi-platform-controller@sha256:5ad0dab50bd7f1f1b0cecc790d722f6daebe85df15a6d2a11519a505f2e9c386"
    "quay.io/konflux-ci/multi-platform-controller@sha256:078a593ab431ac8205e80e4770d98de82fc2fa26c4e913e96043280b82426b68"
    "quay.io/konflux-ci/multi-platform-controller@sha256:2c4c6d71ad4b34dbf174391f953bb2c53da26b22cb86349db077cfc6f667430f"
    "quay.io/konflux-ci/multi-platform-controller@sha256:b82f742a8286007a0b9f994435901639649c059a22df6c7d0926db26a76702e2"
    "quay.io/konflux-ci/multi-platform-controller@sha256:7275bd4b9106fb75b7328df7c1116d8f3f00a5e63c510b5087ec7f9b12d78e25"
    "quay.io/konflux-ci/multi-platform-controller@sha256:e18b9b914ecdb740f0d7e052a4bd14ea75b39b935ab6e5976a64dd52fd6f155a"
    "quay.io/konflux-ci/multi-platform-controller@sha256:b34d813d20d54b333008618d88d5fb307c4f9eed1168e1cc601a08a7cd314315"
    "quay.io/konflux-ci/multi-platform-controller@sha256:33acf8ba6d7270585fea71ab8845561e2a260458951855c0a1c47887b945c12b"
    "quay.io/konflux-ci/multi-platform-controller@sha256:c49b7f009f75745c9556fa1a19b17c83e509ae714a0eb6cccafd1ce773c83d06"
    "quay.io/konflux-ci/multi-platform-controller@sha256:5626af631d86d2496328c428cff725695dcff9ba9e72281e88823936846a9909"
    "quay.io/konflux-ci/multi-platform-controller@sha256:c9107c7f0c24503dc1bd815b165bdc1fa29f0b4188d84aaeb6479a530a6a8748"
    "quay.io/konflux-ci/multi-platform-controller@sha256:d8075a11e7522aa0532ce20155919bc5bfb2a90f83a6e27f0ba2e28eef153613"
    "quay.io/konflux-ci/integration-service@sha256:6bbace3722b3eb2fe740fd5f25b1b15baf1539eaa749a9987e29efeb6a88337f"
    "quay.io/konflux-ci/integration-service@sha256:043c612d09250010cb7dac1c8d8dd469b2d36cbbad4bf6d4663f6357764d9bf3"
    "quay.io/konflux-ci/integration-service@sha256:7d57c8c6e45a7198e4fc0af3ee318c5ca9fcb34192e3944193dfcc892066ef99"
    "quay.io/konflux-ci/integration-service@sha256:7bf081fc506dca9f5f4bcdcc9c241c134012d4d9a1e3f8b65e230ce021ed22f1"
    "quay.io/konflux-ci/integration-service@sha256:a798c3de24e4f2131cf03a00d3dfefb422c72c8635bbe9d236c9f2a4a5fd8d1a"
    "quay.io/konflux-ci/integration-service@sha256:dbe4e29dc855f2e68589bbb04b55dec10ec3b653b5f6542c9ee71545c4466c8e"
    "quay.io/konflux-ci/integration-service@sha256:17fd0865ccf24e66f4047b9c51a2ad6ece2167de562e710bc3f2c79b3739d413"
    "quay.io/konflux-ci/integration-service@sha256:29f3ad997bae945931c67ad13ad362fe35cfab99d3f7df6f844b6a1444d63a91"
    "quay.io/konflux-ci/integration-service@sha256:ee407a55b307d5c2fbdb6fda9014dedee6e7b32a7c539eeea0045fecacb09568"
    "quay.io/konflux-ci/integration-service@sha256:c354f2788ee645e126075889a082cb943800f888bb515c9a5708285361aec07a"
    "quay.io/konflux-ci/integration-service@sha256:3781ccb7eed2190f6375b8e825225bd80767f59a624bf79931388b0ebd7567cd"
    "quay.io/konflux-ci/integration-service@sha256:f2fa973b3c20af64647eccaddffe60b50eb18e415805963a3f2cb1c256add940"
    "quay.io/konflux-ci/integration-service@sha256:1a46ad924641794cdcc88c4b43d19ca43af3f076c6632149de4b57e382fd467a"
    "quay.io/konflux-ci/build-service@sha256:0f9e3438474b1aaa4d4e4413c7bc18989cc861eb2cb7069cfda14117ba41abe5"
    "quay.io/konflux-ci/build-service@sha256:fd085db4497a52fbe275f60dff92ed15b415619937a11b8a04248f1c6576379f"
    "quay.io/konflux-ci/build-service@sha256:4b591a1361d594ab7c9ef006ecfaffc33e34ec782a465c7aa2f77cc4dae21999"
    "quay.io/konflux-ci/build-service@sha256:93cdc2704ed651fedd5a1d4a345f4d1c0cee2f78132548318e055fdda2020955"
    "quay.io/konflux-ci/build-service@sha256:5402e3d3c3eb2ab852b4244c79f0a6be6784657286d86771c487f7d6e87692ab"
    "quay.io/konflux-ci/build-service@sha256:dbb5c07c2fd8f765147283af174ddf4d17957d73bd96449d42b952a9e2785021"
    "quay.io/konflux-ci/build-service@sha256:0c94a0571df7f7e03ee99e789187453acf72852f07900c29f9e0a83033c737b1"
    "quay.io/konflux-ci/build-service@sha256:a41db841fee38e9c993c0b02fa559be19931375bbddf169cd3f0fd2cce15ab0d"
    "quay.io/konflux-ci/build-service@sha256:992df86e5ce0977dcd0d05042fadb95f33983902eb5ea1cde2dea63f15da2f89"
    "quay.io/konflux-ci/notification-service@sha256:c26c7b047f8468a5a28c0bc9d6bf6d35f8b39636dd34358b82d41c34e017c57b"
    "quay.io/konflux-ci/notification-service@sha256:221a99606b99e21a404b94cf18dda0f7b7c23cf9a2824b6a72b08d008d531972"
    "quay.io/konflux-ci/notification-service@sha256:a077ce819e19d62c97d022521a48f80b76195ffae017d7104ca1969e4a9afdad"
    "quay.io/konflux-ci/notification-service@sha256:ef36c5e5ea4d169c6d93da371c99ea51a71e995882b376d23ffc78204a1ea989"
    "quay.io/konflux-ci/notification-service@sha256:44c27d20ed3eeb572719728123ed9663d65c0b40795825b51c8bf7aef36e70e3"
    "quay.io/konflux-ci/notification-service@sha256:6317a6d32eb45272af250a64c27a751b79146408632a95883e152e8eaf9dbf23"
    "quay.io/konflux-ci/notification-service@sha256:a759c5ef934434d36e65470f77039071ac522963ac73aac31d5c02ad81be408c"
    "quay.io/konflux-ci/notification-service@sha256:4a9d0f3d8f6b8f70ba88058650aa973f2892a9cb422a79bf182c985cf130cd47"
    "quay.io/konflux-ci/notification-service@sha256:a94b95af238e541f45fa678fdfcef3f4c7918e7b22dd5bd12cea413b07c4af57"
    "quay.io/konflux-ci/notification-service@sha256:010c461e708f7a987adac4a16448262b46e88af95e1f450221a6ff74e69dc8cd"
    "quay.io/konflux-ci/notification-service@sha256:d669efbd3774d927e732fdad6580a7430df8d678fca304cd664b1ecee6a21396"
    "quay.io/konflux-ci/notification-service@sha256:8787af41c824017b7a3ddaf89258483d6deb09807dd5f4f16bb2ac6456bf9458"
    "quay.io/konflux-ci/notification-service@sha256:c1bce67916b806fcac1ba9277e149ebce54a02c2e7064886a974299216647744"
    "quay.io/konflux-ci/notification-service@sha256:7dee0b6ccda70515e06a5832b9b2fbf43e442b05e7758bc7d7152d18d1ed1ac2"
    "quay.io/konflux-ci/notification-service@sha256:58ab9da66659d8742991cea4722f393f6d7e094fdb6007125f03f73888a6b52f"
    "quay.io/konflux-ci/notification-service@sha256:93a44a0d5543957e06f237cb9b69ff682c19307d826b9402aa3f39f11a3cc831"
    "quay.io/konflux-ci/notification-service@sha256:5368dc2941a9fe0375e0b66e6b311ce5bc86796d1d8f5baadcf3b8b6f7ddf8db"
    "quay.io/konflux-ci/notification-service@sha256:e0bc1f91d00dd2a5e6b754a12bae8027ef90a59643f821b55062a6d7636df772"
    "quay.io/konflux-ci/notification-service@sha256:10a969b50841ecc0942e977a4901529d74a06b71c2b4d06191e0ca27ee7b0e6d"
    "quay.io/konflux-ci/notification-service@sha256:f096802fc4fdcf776071f3d995378e893d22a2c633e3cabec0928d11551b669c"
    "quay.io/konflux-ci/notification-service@sha256:8120aaa408a409efa06e801d8967ea3b0e3d049ad4777900ec2f5f86bd244168"
    "quay.io/konflux-ci/notification-service@sha256:70b12886a3aae2fecfc4940b0c8de0ffc4bca50500cb4fd9eee4245b17500db6"
    "quay.io/konflux-ci/notification-service@sha256:88af547fcab3fc1f12b5ad360869e42f9cd9ec8796ae98f3d77ab8dd6a9c6949"
    "quay.io/konflux-ci/notification-service@sha256:1967444735a0a58da95f019094c47fde6b75824b6fe30a17540a60c992f213c4"
    "quay.io/konflux-ci/notification-service@sha256:239429045d6f9dc4a8712fe632dc00fc5a575e80861f92bd3991cdebb448384b"
    "quay.io/konflux-ci/notification-service@sha256:0e22a612a7de3ff2c0035e95611eda48c6dc8bf21015d9e17e39684c0b45089b"
    "quay.io/konflux-ci/notification-service@sha256:7f6f8ffc0ae89f94cf779052c69b216aa0c1a16a12b91b8c4c50f5dfdc881095"
    "quay.io/konflux-ci/notification-service@sha256:312325aa11409c14624b8e8d02b1f4f7606310a7d84f982d23c23b578fa3747a"
    "quay.io/konflux-ci/notification-service@sha256:96b864297b3bf3ded29b6af4ef92e77f0bc2f5863fec7573974e37138043f957"
    "quay.io/konflux-ci/notification-service@sha256:8e05fdf69a5578557de437c2094ffd6f36c8da50b621ded2257c0ebc7c4f2648"
    "quay.io/konflux-ci/notification-service@sha256:00fe500d7d17ec65e0f187691cc5f0035c188cb6e7b8bb6cffe6186aa7aa12af"
    "quay.io/konflux-ci/notification-service@sha256:96c3551621af66d1a9fc7e2d01ad5c3221dce13a16c71a06f41849f4d1d7236d"
    "quay.io/konflux-ci/notification-service@sha256:d5a03eef9bf0fc70367678b572ad41ed3c1549ef19125cd3b11374f092b8f7ae"
    "quay.io/konflux-ci/notification-service@sha256:697a604c4e0656285cdc9ad30aec5bc93cefce5123cb955465f5a44b50ae6817"
    "quay.io/konflux-ci/notification-service@sha256:ac287c0849e063efc3b83de7b2823efeb3d428807dbd523c313b1409ffb4010a"
    "quay.io/konflux-ci/notification-service@sha256:494677d2ed5d4b6aa2f7cf18152bec45829afa0ea994aa88efbee0c33639d9cf"
    "quay.io/konflux-ci/notification-service@sha256:4d7b5e26f76e5db34695d85c08b959f4da4c444d08371eb3a4f3660f9eb07a1f"
    "quay.io/konflux-ci/notification-service@sha256:08a3a2b46cd50a7d851b4fab8991026dd4e19fa29cc1f8a8ece3aeba4c1afc42"
    "quay.io/konflux-ci/notification-service@sha256:a988df1664001958b4f2b3e4e4058097785aec00463f8e22571ea949d1cc853e"
    "quay.io/konflux-ci/notification-service@sha256:24006c24af77610f19a1869839c4a35aee42b7d88dd697ad282dfe39c189f85e"
    "quay.io/konflux-ci/notification-service@sha256:d0f086c7a0de6e3a17f393b2b0a158df993893dd00051eed612c654112fcac5f"
    "quay.io/konflux-ci/notification-service@sha256:a207a2112f7b8db1f5bb9575d56cd3cca2d02b716ce8cce58066b670f89a800c"
    "quay.io/konflux-ci/notification-service@sha256:431795149aae270b96fd74efdb58b5e74cfe69f1d21c21e01e64cb26fb5d247b"
    "quay.io/konflux-ci/notification-service@sha256:d3f13878b30aa307c75c0490503dc54008638caff66c96e126a4c16d60ba9b83"
    "quay.io/konflux-ci/notification-service@sha256:8903e86365c77b12f1bba9ef34339ce3c1aaac1ffbc59433a5f2942035fca49f"
    "quay.io/konflux-ci/notification-service@sha256:31f002dc33804282e845a8242495e82b16fbaf0b1cda2a5765132a1ed073a781"
    "quay.io/konflux-ci/notification-service@sha256:d178d5f820b7165ce0ed34e3f6bcf68db299b1987bdf5264ff0ec11e58b4a82a"
    "quay.io/konflux-ci/notification-service@sha256:8fc4ad968a09141e07d28fb473edc68135f8addd3ae5350413d8b5b804888119"
    "quay.io/konflux-ci/release-service-utils@sha256:45051bb4ad94bc028712f9b0cda868ec842ed65c7a122779dde976d71a1be1f6"
    "quay.io/konflux-ci/release-service-utils@sha256:1b9972d24198b68def3856c6e3af932be4c46581fda67a0a32f62e33164cd7e2"
    "quay.io/konflux-ci/release-service-utils@sha256:4088080ff19091e2b8f85b63d1e966f40912206c0e39d15b4046ecd36662eb12"
    "quay.io/konflux-ci/release-service-utils@sha256:31ca998a604ffbbd20ad6073e26256490d4adaecd5b21fe2498d65a25aebad37"
    "quay.io/konflux-ci/release-service-utils@sha256:d4ba7427dc0c5bf1e9ee69ad40925ad39094dc599b520a8693875cd27ad6cffc"
    "quay.io/konflux-ci/release-service-utils@sha256:e8689bb3ffac1e2894a08f9c991a788a5aca72e99648cd32100c76a0a4b42c0e"
    "quay.io/konflux-ci/release-service-utils@sha256:4fcb4bae2038efe850379a05b5d03a45cf4c526937b793e1a9460ce619e5c605"
    "quay.io/konflux-ci/release-service-utils@sha256:017c83bb5b09bf9ced13d61dd3f51c3d0b10fc73908164495a2f09d0cda86dd5"
)

# Function to check SBOM format (returns 0 for SPDX, 1 for non-SPDX)
check_sbom_format() {
    local digest_ref="$1"
    local tmpfile=$(mktemp)
    local result=1
    
    if cosign download sbom --output-file "$tmpfile" "$digest_ref" 2>&1 | grep -q "text/spdx+json"; then
        result=0
    fi
    
    rm -f "$tmpfile"
    return $result
}

TEMP_FILE=$(mktemp)
VERIFIED_DIGESTS=()
SPDX_COUNT=0
CYCLONEDX_COUNT=0

cleanup() {
    rm -f "${TEMP_FILE}"
}
trap cleanup EXIT

echo "" >&2
echo "📦 Validating SBOM formats in real-time..." >&2
echo "   Checking ${#CANDIDATE_DIGESTS[@]} candidates (2-3 min)" >&2
echo "" >&2

# Validate each digest
for digest_ref in "${CANDIDATE_DIGESTS[@]}"; do
    if check_sbom_format "$digest_ref"; then
        VERIFIED_DIGESTS+=("$digest_ref")
        SPDX_COUNT=$((SPDX_COUNT + 1))
        short_digest="${digest_ref##*@}"
        echo "✓ [${SPDX_COUNT}] SPDX: ${short_digest:0:16}..." >&2
    else
        CYCLONEDX_COUNT=$((CYCLONEDX_COUNT + 1))
    fi
    
    # Stop validation once we have enough
    if [ ${SPDX_COUNT} -ge ${TARGET_COUNT} ]; then
        echo "" >&2
        echo "✅ Found ${SPDX_COUNT} SPDX digests!" >&2
        break
    fi
done

echo "" >&2
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
echo "📊 Validation:" >&2
echo "   ✅ SPDX: ${SPDX_COUNT}" >&2
echo "   ❌ CycloneDX/Other: ${CYCLONEDX_COUNT}" >&2
echo "" >&2

if [ ${SPDX_COUNT} -lt ${TARGET_COUNT} ]; then
    echo "⚠️  Only ${SPDX_COUNT} SPDX digests found (need ${TARGET_COUNT})" >&2
    echo "   Will cycle through available digests" >&2
fi

# Generate pool (cycle if needed to reach target)
SUCCESS_COUNT=0
PASS=1
MAX_PASSES=5

while [ ${SUCCESS_COUNT} -lt ${TARGET_COUNT} ] && [ ${PASS} -le ${MAX_PASSES} ]; do
    if [ ${PASS} -gt 1 ]; then
        echo "🔄 Pass ${PASS}" >&2
    fi
    
    for digest_ref in "${VERIFIED_DIGESTS[@]}"; do
        echo "${digest_ref}" >> "${TEMP_FILE}"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        
        if [ ${SUCCESS_COUNT} -ge ${TARGET_COUNT} ]; then
            break 2
        fi
    done
    
    PASS=$((PASS + 1))
done

cat "${TEMP_FILE}" > "${OUTPUT_FILE}"

echo "" >&2
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
echo "📊 Final:" >&2
echo "   Total: ${SUCCESS_COUNT} components" >&2
echo "   Unique: ${SPDX_COUNT} SPDX digests" >&2
if [ ${SUCCESS_COUNT} -gt ${SPDX_COUNT} ]; then
    echo "   Reused: $((SUCCESS_COUNT - SPDX_COUNT))" >&2
fi
echo "   Output: ${OUTPUT_FILE}" >&2
echo "" >&2

if [ ${SUCCESS_COUNT} -lt ${TARGET_COUNT} ]; then
    echo "❌ ERROR: Only ${SUCCESS_COUNT}/${TARGET_COUNT} components generated" >&2
    exit 1
fi

echo "✅ Pool ready: ${SUCCESS_COUNT} components with verified SPDX SBOMs" >&2
