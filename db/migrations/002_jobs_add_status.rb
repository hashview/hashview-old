Sequel.migration do
  change do

    alter_table(:jobs) do
      add_column :started_at, DateTime
      add_column :ended_at, DateTime
    end

    alter_table(:hashcat_settings) do
      add_column :optimized_drivers, TrueClass
    end
  end
end

