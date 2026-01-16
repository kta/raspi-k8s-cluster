Vagrant.configure("2") do |config|
  # OSは Ubuntu 22.04 (ラズパイのUbuntu Serverとほぼ同じ挙動)
  config.vm.box = "bento/debian-13"
  
  # 3台共通のリソース設定 (K8sは最低2GB必要)
  config.vm.provider "virtualbox" do |vb|
    vb.memory = "2048"
    vb.cpus = 2
  end

  # --- Node 1 ---
  config.vm.define "vm-node1" do |node|
    node.vm.hostname = "vm-node1"
    node.vm.network "private_network", ip: "192.168.56.101"
  end

  # --- Node 2 ---
  config.vm.define "vm-node2" do |node|
    node.vm.hostname = "vm-node2"
    node.vm.network "private_network", ip: "192.168.56.102"
  end

  # --- Node 3 ---
  config.vm.define "vm-node3" do |node|
    node.vm.hostname = "vm-node3"
    node.vm.network "private_network", ip: "192.168.56.103"
  end
end
