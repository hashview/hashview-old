# encoding: utf-8
get '/download' do
  varWash(params)

  if params[:graph] && !params[:graph].empty?
    # What kind of graph data are we dealing with here
    if params[:graph] == '1'    # Total Hashes Cracked
      # Do Something
    elsif params[:graph] == '2' # Composition Breakdown
      # Do Something
    elsif params[:graph] == '3' # Analysis Detail
      @filecontents = Set.new
      file_name = 'error.txt'
      if params[:customer_id] && !params[:customer_id].empty?
        if params[:hashfile_id] && !params[:hashfile_id].nil?
          # Customer and Hashfile
          if params[:type] == 'cracked'
            @results = repository(:default).adapter.select('SELECT a.username, h.originalhash, h.plaintext FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id LEFT JOIN hashfiles f on a.hashfile_id = f.id WHERE (f.customer_id = ? AND a.hashfile_id = ? and h.cracked = 1)', params[:customer_id],params[:hashfile_id])
            file_name = "found_#{params[:customer_id]}_#{params[:hashfile_id]}.txt"
          elsif params[:type] == 'uncracked'
            @results = repository(:default).adapter.select('SELECT a.username, h.originalhash FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id LEFT JOIN hashfiles f on a.hashfile_id = f.id WHERE (f.customer_id = ? AND f.hashfile_id = ? and h.cracked = 0)', params[:customer_id],params[:hashfile_id])
            file_name = "left_#{params[:customer_id]}_#{params[:hashfile_id]}.txt"
          else
            # Do Something
            file_name = 'error.txt'
          end
        else
          # Just Customer
          if params[:type] == 'cracked'
            @results = repository(:default).adapter.select('SELECT a.username, h.originalhash, h.plaintext FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id LEFT JOIN hashfiles f on a.hashfile_id = f.id WHERE (f.customer_id = ? and h.cracked = 1)', params[:customer_id])
            file_name = "found_#{params[:customer_id]}.txt"
          elsif params[:type] == 'uncracked'
            @results = repository(:default).adapter.select('SELECT a.username, h.originalhash FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id LEFT JOIN hashfiles f on a.hashfile_id = f.id WHERE (f.customer_id = ? and h.cracked = 0)', params[:customer_id])
            file_name = "left_#{params[:customer_id]}.txt"
          else
            # Do Something
            file_name = 'error.txt'
          end
        end
      else
        # All
        if params[:type] == 'cracked'
          @results = repository(:default).adapter.select('SELECT a.username, h.originalhash, h.plaintext FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id LEFT JOIN hashfiles f on a.hashfile_id = f.id WHERE (h.cracked = 1)')
          file_name = 'found_all.txt'
        elsif params[:type] == 'uncracked'
          @results = repository(:default).adapter.select('SELECT a.username, h.originalhash FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id LEFT JOIN hashfiles f on a.hashfile_id = f.id WHERE (h.cracked = 0)')
          file_name = 'left_all.txt'
        else
          # Do Something
          file_name = 'error.txt'
        end
      end

      @results.each do |entry|
        entry.username.nil? ? line = '' : line = entry.username.to_s + ':'
        line += entry.originalhash.to_s
        line += ':' + entry.plaintext.to_s if params[:type] == 'cracked'
        @filecontents.add(line)
      end

      file_name = 'control/tmp/' + file_name

      File.open(file_name, 'w') do |f|
        @filecontents.each do |entry|
          f.puts entry
        end
      end

      send_file file_name, filename: file_name, type: 'Application/octet-stream'
    elsif params[:graph] == '4' # Password Count by Length
      # Do Something
    elsif params[:graph] == '5' # Top 10 Passwords
      # Do Something
    elsif params[:graph] == '6' # Accounts With Weak Passwords
      file_name = 'error.txt'
      if params[:customer_id] && !params[:customer_id].empty?
        if params[:hashfile_id] && !params[:hashfile_id].nil?
          @complexity_hashes = repository(:default).adapter.select('SELECT a.username, h.plaintext FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id WHERE (a.hashfile_id = ? AND h.cracked = 1)', params[:hashfile_id])
          file_name = "Weak_Accounts_#{params[:customer_id]}_#{params[:hashfile_id]}.csv"
        else
          @complexity_hashes = repository(:default).adapter.select('SELECT a.username, h.plaintext FROM hashes h LEFT JOIN hashfilehashes a on h.id = a.hash_id LEFT JOIN hashfiles f on a.hashfile_id = f.id WHERE (f.customer_id = ? AND h.cracked = 1)', params[:customer_id])
          file_name = "Weak_Accounts_#{params[:customer_id]}.csv"
        end
      else
        @complexity_hashes = repository(:default).adapter.select('SELECT a.username, h.plaintext FROM hashes h LEFT JOIN hashfilehashes a on h.id = a.hash_id LEFT JOIN hashfiles f on a.hashfile_id = f.id WHERE (h.cracked = 1)')
        file_name = "Weak_Accounts_all.csv"
      end

      file_name = 'control/tmp/' + file_name

      File.open(file_name, 'w') do |f|
        line = 'username,password'
        f.puts line
        @complexity_hashes.each do |entry|
          unless entry.plaintext.to_s =~ /^(?:(?=.*[a-z])(?:(?=.*[A-Z])(?=.*[\d\W])|(?=.*\W)(?=.*\d))|(?=.*\W)(?=.*[A-Z])(?=.*\d)).{8,}$/
            line = entry.username.to_s + ',' + entry.plaintext.to_s
            f.puts line
          end
        end
      end

      send_file file_name, filename: file_name, type: 'Application/octet-stream'

    elsif params[:graph] == '7' # Top 20 Password/Hashes Shared by Users
      # Do something
    else
      # DO Something
    end
  end
end

