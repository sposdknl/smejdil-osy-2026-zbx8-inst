Vagrant.configure("2") do |config|
  config.vm.box = "bento/freebsd-14.3"
  config.vm.hostname = "spos-zabbix8"
  config.ssh.insert_key = false

  config.vm.network "forwarded_port", guest: 80, host: 8080, host_ip: "127.0.0.1"
  config.vm.network "forwarded_port", guest: 22, host: 2211, host_ip: "127.0.0.1"

  config.vm.provider "virtualbox" do |vb|
    vb.name = "spos-zabbix8-freebsd143"
    vb.memory = 4096
    vb.cpus = 2
  end

  config.vm.provision "shell", path: "scripts/install.sh"
end
