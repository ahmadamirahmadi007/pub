#!/bin/bash -x

# ./create-kubernetes-binaries-iso.sh ./ 1.28.11 1.5.1 1.30.0 https://raw.githubusercontent.com/ahmadamirahmadi007/pub/main/network.yaml https://raw.githubusercontent.com/ahmadamirahmadi007/pub/main/recommended.yaml setup-v1.28.11
set -e

if [ $# -lt 6 ]; then
    echo "Invalid input. Valid usage: ./create-kubernetes-binaries-iso.sh OUTPUT_PATH KUBERNETES_VERSION CNI_VERSION CRICTL_VERSION WEAVENET_NETWORK_YAML_CONFIG DASHBOARD_YAML_CONFIG BUILD_NAME"
    echo "eg: ./create-kubernetes-binaries-iso.sh ./ 1.11.4 0.7.1 1.11.1 https://github.com/weaveworks/weave/releases/download/latest_release/weave-daemonset-k8s-1.11.yaml https://raw.githubusercontent.com/kubernetes/dashboard/v1.10.0/src/deploy/recommended/kubernetes-dashboard.yaml setup-v1.11.4"
    exit 1
fi

RELEASE="v${2}" # 1.28.11
VAL="1.18.0"
output_dir="${1}" # ./
start_dir="$PWD"  # /root
iso_dir="/tmp/iso" # /tmp/iso
working_dir="${iso_dir}/" # /tmp/iso/
mkdir -p "${working_dir}" # Create iso Directory In /tmp/
build_name="${7}.iso" # setup-v1.28.11
[ -z "${build_name}" ] && build_name="setup-${RELEASE}.iso"

CNI_VERSION="v${3}" # 1.5.1
echo "Downloading CNI ${CNI_VERSION}..."
cni_dir="${working_dir}/cni/" # /tmp/iso/cni/
mkdir -p "${cni_dir}" # Create cni Directory In /tmp/iso/cni/
cni_status_code=$(curl -L  --write-out "%{http_code}\n" "https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-linux-amd64-${CNI_VERSION}.tgz" -o "${cni_dir}/cni-plugins-amd64.tgz")

CRICTL_VERSION="v${4}" # 1.30.0
echo "Downloading CRI tools ${CRICTL_VERSION}..."
crictl_dir="${working_dir}/cri-tools/" # /tmp/iso/cri-tools/
mkdir -p "${crictl_dir}" # Create cri-tools Directory In /tmp/iso/
curl -L "https://github.com/kubernetes-incubator/cri-tools/releases/download/${CRICTL_VERSION}/crictl-${CRICTL_VERSION}-linux-amd64.tar.gz" -o "${crictl_dir}/crictl-linux-amd64.tar.gz"

echo "Downloading Kubernetes tools ${RELEASE}..."
k8s_dir="${working_dir}/k8s"  # /tmp/iso/k8s
mkdir -p "${k8s_dir}" # Create k8s Directory in /tmp/iso/
cd "${k8s_dir}" # cd # /tmp/iso/k8s
curl -L --remote-name-all https://storage.googleapis.com/kubernetes-release/release/${RELEASE}/bin/linux/amd64/{kubeadm,kubelet,kubectl}
kubeadm_file_permissions=`stat --format '%a' kubeadm`
chmod +x kubeadm

echo "Downloading kubelet.service ${RELEASE}..."
cd "${start_dir}" # /root
kubelet_service_file="${working_dir}/kubelet.service" # /tmp/iso/kubelet.service
touch "${kubelet_service_file}" # touch /tmp/iso/kubelet.service
if [[ `echo "${2} $VAL" | awk '{print ($1 < $2)}'` == 1 ]]; then
  curl -sSL "https://raw.githubusercontent.com/kubernetes/kubernetes/${RELEASE}/build/debs/kubelet.service" | sed "s:/usr/bin:/opt/bin:g" > ${kubelet_service_file}
else
  curl -sSL "https://raw.githubusercontent.com/shapeblue/cloudstack-nonoss/main/cks/kubelet.service" | sed "s:/usr/bin:/opt/bin:g" > ${kubelet_service_file}
fi

echo "Downloading 10-kubeadm.conf ${RELEASE}..."
kubeadm_conf_file="${working_dir}/10-kubeadm.conf" # /tmp/iso/10-kubeadm.conf
touch "${kubeadm_conf_file}" # touch /tmp/iso/10-kubeadm.conf
if [[ `echo "${2} $val" | awk '{print ($1 < $2)}'` == 1 ]]; then
  curl -sSL "https://raw.githubusercontent.com/kubernetes/kubernetes/${RELEASE}/build/debs/10-kubeadm.conf" | sed "s:/usr/bin:/opt/bin:g" > ${kubeadm_conf_file}
else
  curl -sSL "https://raw.githubusercontent.com/shapeblue/cloudstack-nonoss/main/cks/10-kubeadm.conf" | sed "s:/usr/bin:/opt/bin:g" > ${kubeadm_conf_file}
fi

NETWORK_CONFIG_URL="${5}" # 1th URL
echo "Downloading network config ${NETWORK_CONFIG_URL}"
network_conf_file="${working_dir}/network.yaml" # /tmp/iso/network.yaml
curl -sSL ${NETWORK_CONFIG_URL} -o ${network_conf_file}  # /tmp/iso/network.yaml

DASHBORAD_CONFIG_URL="${6}"
echo "Downloading dashboard config ${DASHBORAD_CONFIG_URL}"
dashboard_conf_file="${working_dir}/dashboard.yaml"
curl -sSL ${DASHBORAD_CONFIG_URL} -o ${dashboard_conf_file}

# TODO : Change the url once merged
AUTOSCALER_URL="https://raw.githubusercontent.com/kubernetes/autoscaler/master/cluster-autoscaler/cloudprovider/cloudstack/examples/cluster-autoscaler-standard.yaml"
echo "Downloading kubernetes cluster autoscaler ${AUTOSCALER_URL}"
autoscaler_conf_file="${working_dir}/autoscaler.yaml"
curl -sSL ${AUTOSCALER_URL} -o ${autoscaler_conf_file}

PROVIDER_URL="https://raw.githubusercontent.com/apache/cloudstack-kubernetes-provider/main/deployment.yaml"
echo "Downloading kubernetes cluster provider ${PROVIDER_URL}"
provider_conf_file="${working_dir}/provider.yaml"
curl -sSL ${PROVIDER_URL} -o ${provider_conf_file}

echo "Fetching k8s docker images..."
ctr -v
if [ $? -ne 0 ]; then
    echo "Installing containerd..."
    if [ -f /etc/redhat-release ]; then
      sudo yum -y remove docker-common docker container-selinux docker-selinux docker-engine
      sudo yum -y install lvm2 device-mapper device-mapper-persistent-data device-mapper-event device-mapper-libs device-mapper-event-libs
      sudo yum install -y http://mirror.centos.org/centos/7/extras/x86_64/Packages/container-selinux-2.107-3.el7.noarch.rpm
      sudo yum install -y containerd.io
    elif [ -f /etc/lsb-release ]; then
      sudo apt update && sudo apt install containerd.io -y
    fi
    sudo systemctl enable containerd && sudo systemctl start containerd
fi
mkdir -p "${working_dir}/docker" # /tmp/iso
output=`${k8s_dir}/kubeadm config images list --kubernetes-version=${RELEASE}` # /tmp/iso/k8s

# Don't forget about the yaml images !
for i in ${network_conf_file} ${dashboard_conf_file}
do
  images=`grep "image:" $i | cut -d ':' -f2- | tr -d ' ' | tr -d "'"`
  output=`printf "%s\n" ${output} ${images}`
done

# Don't forget about the other image !
autoscaler_image=`grep "image:" ${autoscaler_conf_file} | cut -d ':' -f2- | tr -d ' '`
output=`printf "%s\n" ${output} ${autoscaler_image}`

provider_image=`grep "image:" ${provider_conf_file} | cut -d ':' -f2- | tr -d ' '`
output=`printf "%s\n" ${output} ${provider_image}`

while read -r line; do
    echo "Downloading image $line ---"
    if [[ $line == kubernetesui* ]] || [[ $line == apache* ]] || [[ $line == weaveworks* ]]; then
      line="docker.io/${line}"
      #line="registry.virakcloud.com/${line}"
    fi
    sudo ctr image pull "$line"
    image_name=`echo "$line" | grep -oE "[^/]+$"`
    sudo ctr image export "${working_dir}/docker/$image_name.tar" "$line"
    sudo ctr image rm "$line"
done <<< "$output"

echo "Restore kubeadm permissions..."
if [ -z "${kubeadm_file_permissions}" ]; then
    kubeadm_file_permissions=644
fi
chmod ${kubeadm_file_permissions} "${working_dir}/k8s/kubeadm"

echo "Updating imagePullPolicy to IfNotPresent in yaml files..."
sed -i "s/imagePullPolicy:.*/imagePullPolicy: IfNotPresent/g" ${working_dir}/*.yaml

mkisofs -o "${output_dir}/${build_name}" -J -R -l "${iso_dir}"

rm -rf "${iso_dir}"


# apache/cloudstack-kubernetes-provider:v1.1.0
# registry.virakcloud.com/weaveworks/weave-kube:latest
# registry.virakcloud.com/weaveworks/weave-kube:latest
# registry.virakcloud.com/weaveworks/weave-npc:latest
# apache/cloudstack-kubernetes-autoscaler:latest

# registry.k8s.io/kube-apiserver:v1.30.2
  #registry.k8s.io/kube-controller-manager:v1.30.2
  #registry.k8s.io/kube-scheduler:v1.30.2
  #registry.k8s.io/kube-proxy:v1.30.2
  #registry.k8s.io/coredns/coredns:v1.11.1
  #registry.k8s.io/pause:3.9
  #registry.k8s.io/etcd:3.5.12-0
