#! /bin/bash


git clone https://github.com/spectrocloud/CanvOS.git
cd CanvOS

# Prompt for confirmation
read -p "Use latest CanvOS (y/n)
  " confirm

# Check the response
if [[ "$confirm" == "y" || "$confirm" == "" ]]; then
  #use the latest available
  canvos=$(git describe --tags $(git rev-list --tags --max-count=1))
  echo "Using Latest CanvOS"
elif [[ "$confirm" == "n" ]]; then
  #display all versions
  git tag | column
  read -p "Select CanvOS Version:
  " canvos 
else
  echo "Invalid input."
fi

git checkout $canvos


read -p "Enter a custom tag for this build:
  " custom_tag
if [[ "$custom_tag" == "" ]]; then
  custom_tag="palette"
fi


read -p "Registry for Provider Image - No HTTP(S):// ! 
ex: harbor.test.com/edge

Leave blank for ttl.sh
  " image_registry
if [[ "$image_registry" == "" ]]; then
  image_registry="ttl.sh"
fi

read -p "OS, leave blank for ubuntu:
  " os
if [[ "$os" == "" ]]; then
  os="ubuntu"
fi

read -p "OS Version, leave blank for 22.04:
  " os_version
if [[ "$os_version" == "" && $os == "ubuntu" ]]; then
  os_version="22.04"
fi

read -p "Image Repo, leave blank for OS chosen above:
  " image_repo
if [[ "$image_repo" == "" ]]; then
  image_repo=$os
fi


read -p "Kubernetes flavor: k3s, kubeadm, rke2, kubeadm-fips, nodeadm:
  " k8s_distribution
if [[ "$k8s_distribution" == "" ]]; then
  k8s_distribution="k3s"
fi

echo "Possible versions for $k8s_distribution:
"  
json=$(jq -c ".${k8s_distribution}[]"  ./k8s_version.json)
json_without_quotes=$(echo ${json//\"/""})
IFS=$' ' read -r -d '' -a array <<< "$json_without_quotes"
latest_k8s=$(echo ${array[-1]} | tr -d '\n')

printf "%s\n" ${json_without_quotes}  

read -p "
K8s Version:
  " k8s_version
if [[ "$k8s_version" == "" ]]; then
  echo "Using latest version: $latest_k8s"
  k8s_version="$latest_k8s"
fi


read -p "ISO Name, Leave blank to use: 
  $custom_tag-edge:$canvos-$os:$os_version-$k8s_distribution:$k8s_version.iso
  " iso_name

if [[ "$iso_name" == "" ]]; then
  iso_name="$custom_tag-edge:$canvos-$os:$os_version-$k8s_distribution:$k8s_version"
  echo "Image Name set as: 
  $iso_name.iso
  "
fi


base_image=""
if [[ "$os" == "slem" ]]; then
  read -p "Base Image for SLEM/SLES
  Default if no input: docker.io/3pings/sles-m:v5.4-v21
  " base_image
fi


read -p "Update Kernel? true/false:
  " kernel
if [[ "$kernel" == "" ]]; then
  kernel="false"
fi


arg="CUSTOM_TAG=${custom_tag}
IMAGE_REGISTRY=${image_registry}
OS_DISTRIBUTION=${os}
OS_VERSION=${os_version}
IMAGE_REPO=${image_repo}
K8S_DISTRIBUTION=${k8s_distribution}
K8S_VERSION=${k8s_version}
ISO_NAME=${iso_name}
ARCH=amd64
${base_image}
UPDATE_KERNEL=${kernel}"

echo "
arg file looks like:
 
$arg

"

echo "$arg" > .arg


read -p "Edge Host Token:
  " edgehosttoken
read -p "Palette Endpoint. Leave blank for api.spectrocloud.com:
  " paletteendpoint
if [[ "$paletteendpoint" == "" ]]; then
  paletteendpoint="api.spectrocloud.com"
fi

read -p "Include TUI? true/false, defaults to false
  " tui
if [[ "$tui" == "" ]]; then
  tui="false"
fi


user_data="#cloud-config
stylus:
  includeTui: ${tui}
  site:
    paletteEndpoint: ${paletteendpoint}
    edgeHostToken: ${edgehosttoken}

install:
  poweroff: true

stages:
  initramfs:
    - users:
        kairos:
          groups:
            - sudo
          passwd: kairos
      name: Create user and assign to sudo group"


echo "User data looks like: 
echo $user_data

"

echo "$user_data" > user-data


# Prompt for ISO Build
read -p "Ready to build ISO? (y/n)
  " confirm

# Check the response
if [[ "$confirm" == "y" ]]; then
  #use the latest available
  ./earthly.sh +iso

elif [[ "$confirm" == "n" || "$confirm" == "" ]]; then
  echo "Build ISO with ./earthly.sh +iso"
else
  echo "Invalid input."
fi




byos_template='pack:
  content:
    images:
      - image: "{{.spectro.pack.edge-native-byoi.options.system.uri}}"
  # Below config is default value, please uncomment if you want to modify default values
  #drain:
    #cordon: true
    #timeout: 60 # The length of time to wait before giving up, zero means infinite
    #gracePeriod: 60 # Period of time in seconds given to each pod to terminate gracefully. If negative, the default value specified in the pod will be used
    #ignoreDaemonSets: true
    #deleteLocalData: true # Continue even if there are pods using emptyDir (local data that will be deleted when the node is drained)
    #force: true # Continue even if there are pods that do not declare a controller
    #disableEviction: false # Force drain to use delete, even if eviction is supported. This will bypass checking PodDisruptionBudgets, use with caution
    #skipWaitForDeleteTimeout: 60 # If pod DeletionTimestamp older than N seconds, skip waiting for the pod. Seconds must be greater than 0 to skip.
options:
  system.uri: "{{ .spectro.pack.edge-native-byoi.options.system.registry }}/{{ .spectro.pack.edge-native-byoi.options.system.repo }}:{{ .spectro.pack.edge-native-byoi.options.system.k8sDistribution }}-{{ .spectro.system.kubernetes.version }}-{{ .spectro.pack.edge-native-byoi.options.system.peVersion }}-{{ .spectro.pack.edge-native-byoi.options.system.customTag }}"

'
byos_data="
  system.registry: ${image_registry} 
  system.repo: ${image_repo}
  system.k8sDistribution: ${k8s_distribution}
  system.osName: ${os}
  system.peVersion: ${canvos}
  system.customTag: ${custom_tag}
  system.osVersion: ${os_version}"

echo "${byos_template} ${byos_data}" > "${custom_tag}-provider.yaml"



# Prompt for Provider Image Build
read -p "Ready to build Provider Image? (y/n)
  " confirm

# Check the response
if [[ "$confirm" == "y" ]]; then

  #Build the Provider image
  ./earthly.sh +build-provider-images

  echo "Pushing Provider image to Docker Registry:
  docker push ${image_registry}/${os}:${k8s_distribution}-${k8s_version}-${canvos}-${custom_tag}"

  docker push ${image_registry}/${os}:${k8s_distribution}-${k8s_version}-${canvos}-${custom_tag}


elif [[ "$confirm" == "n" || "$confirm" == "" ]]; then
  echo "Build Provider Image with ./earthly.sh +build-provider-images"
  echo "Push Provider Image with:
  docker push ${image_registry}/${os}:${k8s_distribution}-${k8s_version}-${canvos}-${custom_tag}
  "
else
  echo "Invalid input."
fi


