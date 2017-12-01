Sequel.migration do
  change do
    create_table(:agents) do
      primary_key :id, :type=>:Bignum
      String :name, :size=>100
      String :src_ip, :size=>45
      String :uuid, :size=>60
      String :status, :size=>40
      String :hc_status, :size=>6000
      DateTime :heartbeat
      String :benchmark, :size=>6000
      String :devices, :size=>6000
      Integer :cpu_count
      Integer :gpu_count
    end
    
    create_table(:customers) do
      primary_key :id, :type=>:Bignum
      String :name, :size=>40
      String :description, :size=>500
    end
    
    create_table(:hashcat_settings) do
      primary_key :id, :type=>:Bignum
      String :hc_binpath, :size=>2000
      String :max_task_time, :size=>2000
      Integer :opencl_device_types, :default=>0
      Integer :workload_profile, :default=>0
      TrueClass :gpu_temp_disable, :default=>false
      Integer :gpu_temp_abort, :default=>0
      Integer :gpu_temp_retain, :default=>0
      TrueClass :hc_force, :default=>false
    end
    
    create_table(:hashes, :ignore_index_errors=>true) do
      primary_key :id
      DateTime :lastupdated
      String :originalhash, :size=>1024
      Integer :hashtype
      TrueClass :cracked
      String :plaintext, :size=>256
      
      index [:hashtype], :name=>:index_of_hashtypes
      index [:originalhash], :name=>:index_of_orignalhashes, :unique=>true
    end
    
    create_table(:hashfilehashes, :ignore_index_errors=>true) do
      primary_key :id, :type=>:Bignum
      Integer :hash_id
      String :username, :size=>256
      Integer :hashfile_id
      
      index [:hash_id], :name=>:index_hashfilehashes_hash_id
      index [:hashfile_id], :name=>:index_hashfilehashes_hashfile_id
    end
    
    create_table(:hashfiles) do
      primary_key :id, :type=>:Bignum
      Integer :customer_id
      String :name, :size=>256
      String :hash_str, :size=>256
      Integer :total_run_time, :default=>0
    end
    
    create_table(:hub_settings) do
      primary_key :id, :type=>:Bignum
      TrueClass :enabled
      String :status, :default=>"unregistered", :size=>50, :null=>false
      String :email, :size=>50
      String :uuid, :size=>50
      String :auth_key, :size=>254
      Integer :balance, :default=>0
    end
    
    create_table(:jobs) do
      primary_key :id, :type=>:Bignum
      String :name, :size=>50
      String :last_updated_by, :size=>40
      DateTime :updated_at, :default=>DateTime.parse("2017-08-03T16:06:21.000000000+0000")
      String :status, :size=>100
      DateTime :queued_at
      String :targettype, :size=>2000
      Integer :hashfile_id
      Integer :policy_min_pass_length
      TrueClass :policy_complexity_default
      Integer :customer_id
      TrueClass :notify_completed
    end
    
    create_table(:jobtasks) do
      primary_key :id, :type=>:Bignum
      Integer :job_id
      Integer :task_id
      String :build_cmd, :size=>5000
      String :status, :size=>50
      Integer :run_time
    end
    
    create_table(:rules) do
      primary_key :id, :type=>:Bignum
      DateTime :lastupdated
      String :name, :size=>256
      String :path, :size=>2000
      String :size, :size=>100
      String :checksum, :size=>64
    end
    
    create_table(:sessions) do
      primary_key :id, :type=>:Bignum
      String :session_key, :size=>128
      String :username, :size=>40, :null=>false
    end
    
    create_table(:settings) do
      primary_key :id, :type=>:Bignum
      String :smtp_server, :size=>50
      String :smtp_sender, :size=>50
      String :smtp_user, :size=>50
      String :smtp_pass, :size=>50
      TrueClass :smtp_use_tls
      String :smtp_auth_type, :size=>50
      TrueClass :clientmode
      String :ui_themes, :default=>"Light", :size=>50, :null=>false
      String :version, :size=>5
      Bignum :chunk_size, :default=>500000
      
      check Sequel::SQL::BooleanExpression.new(:>=, Sequel::SQL::Identifier.new(:chunk_size), 0)
    end
    
    create_table(:taskqueues) do
      primary_key :id, :type=>:Bignum
      Integer :jobtask_id
      Integer :job_id
      DateTime :updated_at, :default=>DateTime.parse("2017-08-03T16:06:21.000000000+0000")
      DateTime :queued_at
      String :status, :size=>100
      String :agent_id, :size=>2000
      String :command, :size=>4000
    end
    
    create_table(:tasks, :ignore_index_errors=>true) do
      primary_key :id, :type=>:Bignum
      String :name, :size=>50
      String :source, :size=>50
      String :mask, :size=>50
      String :command, :size=>4000
      String :wl_id, :size=>256
      String :hc_attackmode, :size=>25
      String :hc_rule, :size=>50
      String :hc_mask, :size=>50
      Bignum :keyspace
      
      check Sequel::SQL::BooleanExpression.new(:>=, Sequel::SQL::Identifier.new(:keyspace), 0)

      index [:name, :hc_mask], :name=>:ix_uq, :unique=>true
    end

    create_table(:users) do
      primary_key :id, :null=>false, :auto_increment=>true
      String :username, :size=>40, :null=>false
      String :hashed_password, :size=>128
      TrueClass :admin
      DateTime :created_at, :default=>DateTime.parse("2017-08-03T16:06:21.000000000+0000")
      String :phone, :size=>50
      String :email, :size=>50
      TrueClass :mfa

      check Sequel::SQL::BooleanExpression.new(:>=, Sequel::SQL::Identifier.new(:id), 0)
    end

    create_table(:wordlists) do
      primary_key :id, :type=>:Bignum
      DateTime :lastupdated
      String :type, :size=>25
      String :name, :size=>256
      String :path, :size=>2000
      String :size, :size=>100
      String :checksum, :size=>64
    end
  end
end
