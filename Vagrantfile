Vagrant.configure("2") do |config|
  # OSは Ubuntu 22.04 (ラズパイのUbuntu Serverとほぼ同じ挙動)
  config.vm.box = "bento/debian-13"
  
  # 起動タイムアウト設定 (Apple Silicon対策)
  config.vm.boot_timeout = 600
  
  # 3台共通のリソース設定 (K8sは最低2GB必要)
  config.vm.provider "virtualbox" do |vb|
    vb.memory = "2048"
    vb.cpus = 2
    # Apple Silicon対策: ネットワークアダプタ設定を最適化
    vb.customize ["modifyvm", :id, "--nictype1", "virtio"]
    vb.customize ["modifyvm", :id, "--nictype2", "virtio"]
    vb.customize ["modifyvm", :id, "--cableconnected1", "on"]
    vb.customize ["modifyvm", :id, "--cableconnected2", "on"]
    # GUI無効化を明示
    vb.gui = false
  end

  # --- Node 1 ---
  config.vm.define "vm-node1" do |node|
    node.vm.hostname = "vm-node1"
    node.vm.network "private_network", ip: "192.168.56.101", nic_type: "virtio"
    # ArgoCD NodePort forwarding
    node.vm.network "forwarded_port", guest: 30080, host: 30080, host_ip: "127.0.0.1"
    node.vm.network "forwarded_port", guest: 30443, host: 30443, host_ip: "127.0.0.1"
  end

  # --- Node 2 ---
  config.vm.define "vm-node2" do |node|
    node.vm.hostname = "vm-node2"
    node.vm.network "private_network", ip: "192.168.56.102", nic_type: "virtio"
  end

  # --- Node 3 ---
  config.vm.define "vm-node3" do |node|
    node.vm.hostname = "vm-node3"
    node.vm.network "private_network", ip: "192.168.56.103", nic_type: "virtio"
  end
end
