Vagrant.configure("2") do |config|
  config.vm.box = "cloud-image/fedora-42"
  config.ssh.extra_args = ["-o", "LogLevel=INFO"]
  config.vm.provision "shell", path: "docker.sh", run: "always"

  config.vm.provider :libvirt do |libvirt|
    libvirt.memory = 2048
    libvirt.cpus = 2
    libvirt.default_prefix = "fedora42"
  end

  # Private Network
  config.vm.network "private_network", type: "dhcp"

  # Shared folder configuration
  config.vm.synced_folder ".", "/vagrant", type: "rsync"
end
