Sequel.migration do
  change do

    alter_table(:jobs) do
      add_column :started_at, DateTime
      add_column :ended_at, DateTime
    end
  end
end