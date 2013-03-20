# Install packages
%w(
  git-core
  imagemagick
  postfix
  ).each {|pkg| package pkg }

# Setup deployment group
group "deploy" do
  gid 4000
end

# Setup user directories
node[:users].each_with_index do |user, i|

  # Create user
  user user[:id] do
    gid 4000
    uid "4#{i.to_s.rjust(3, '0')}"
    home "/home/#{user[:id]}"
    shell "/bin/bash"
    password user[:password]
    supports manage_home: true
  end

  # Setup directories
  %w[.ssh git tmp private xfer backup web].each do |dir|
    directory "/home/#{user[:id]}/#{dir}" do
      owner user[:id]
    end
  end

  # Add SSH key
  file "/home/#{user[:id]}/.ssh/authorized_keys" do
    owner user[:id]
    content user[:ssh_key]
  end
  
end

# Include recipes
%w(
   nginx
   postgresql::server
   postgresql::client
   postgresql::ruby
   nodejs
   logrotate
   sudo
   memcached
   ).each {|recipe| include_recipe recipe }

# Setup databases
node[:postgresql][:users].each do |user|
  bash "create postgresl user #{user[:username]}" do
    user "postgres"
    command "createuser -d -a #{user[:username]}"
    not_if "psql -c '\\du' | grep #{user[:username]}"
  end
  user[:databases].each do |db|
    bash "create database #{db} for user #{user[:username]}" do
      user user[:username]
      command "createdb #{db}"
      not_if "psql -c '\\l' | grep #{db}"
    end
  end
end

# Setup nginx config for rails applications
node[:rails_applications].each do |site|

  # Setup git
  git_dir = "/home/#{site[:deploy_user]}/git/#{site[:sitename]}.git"
  bash "Create git repo #{git_dir}" do
    user site[:deploy_user]
    code <<-EOH
      mkdir #{git_dir}
      cd #{git_dir}
      git init --bare
    EOH
    not_if "test -d #{git_dir}"
  end

  # Setup deploy directory
  deploy_path = "/home/#{site[:deploy_user]}/web/#{site[:sitename]}"
  directory deploy_path do
    owner site[:deploy_user]
  end

  # Site template
  template "/etc/nginx/sites-available/#{site[:sitename]}" do
    source "nginx_unicorn.erb"
    mode 0644
    variables(
      :sitename    => site[:sitename],
      :deploy_path => deploy_path,
      :domains     => site[:domains]
    )
  end
  nginx_site site[:sitename]

end
