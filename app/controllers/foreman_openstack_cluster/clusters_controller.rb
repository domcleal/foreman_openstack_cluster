module ForemanOpenstackCluster
  class ClustersController < ::ApplicationController

    def new
      @controller_class = Puppetclass.find_by_name('quickstack::controller')
      @compute_class    = Puppetclass.find_by_name('quickstack::compute')
      not_found and return unless ( @controller_class && @compute_class )

      # Setup the override keys on the classes ahead of time
      set_keys(@controller_class)
      set_keys(@compute_class)

      @cluster = Cluster.new
      Cluster.params.each do |k,v|
        @cluster.send("#{k}=",v[:default])
      end
    end

    def create
      @cluster = Cluster.new(params['foreman_openstack_cluster_cluster'])
      if @cluster.save
        setup_quickstack "quickstack::controller"
        setup_quickstack "quickstack::compute"
        process_success({:success_redirect => hostgroups_path})
      else
        process_error :render => 'foreman_openstack_cluster/clusters/new', :object => @cluster
      end
    end

    private

    def setup_quickstack type
      @qs_class = Puppetclass.find_by_name(type)
      @parent   = Hostgroup.first #replace this with Dom's provisioning group
      name      = "#{params[:foreman_openstack_cluster_cluster][:name]} #{type.split('::').last.capitalize}"

      # Borrowed from Hostgroup#nest
      @hostgroup                = Hostgroup.find_or_create_by_name(name)
      @hostgroup.environment_id = @parent.environment_id
      @hostgroup.parent_id      = @parent.id
      @hostgroup.locations      = @parent.locations
      @hostgroup.organizations  = @parent.organizations
      # Clone any parameters as well
      @hostgroup.group_parameters.each{|param| @parent.group_parameters << param.dup}
      @hostgroup.save

      # Add quickstack stuff
      @hostgroup.puppetclasses = [@qs_class]

      condition = { 'environment_classes.puppetclass_id'=> @qs_class.id }
      keys = LookupKey.smart_class_parameters.where(condition)

      params[:foreman_openstack_cluster_cluster].each do |k,v|
        lk = keys.where(:key => k).first
        next if lk.nil?
        lk.lookup_values.create!( { :match => "hostgroup=#{@hostgroup.label}", :value => v } )
      end
      @hostgroup.save!
    end

    def set_keys pclass
      Cluster.params.each do |k,v|
        if cp = pclass.class_params.find_by_key(k)
          cp.override = true
          if cp.key_type != v[:type].to_s
            # If we alter the key_type we may also break the default so update both
            cp.key_type = v[:type].to_s
            cp.default_value = v[:default].to_s
          end
          cp.save!
        end
      end
    end

  end
end
