# encoding: utf-8
class HashView < Sinatra::Application
  get '/download' do
    varWash(params)
  
    if params[:customer_id] && !params[:customer_id].empty?
      if params[:hashfile_id] && !params[:hashfile_id].nil?
  
        # Until we can figure out JOIN statments, we're going to have to hack it
        @filecontents = Set.new
        Hashfilehashes.all(fields: [:id], hashfile_id: params[:hashfile_id]).each do |entry|
          if params[:type] == 'cracked' and Hashes.first(fields: [:cracked], id: entry.hash_id).cracked
            if entry.username.nil? # no username
              line = ''
            else
              line = entry.username + ':'
            end
            line = line + Hashes.first(fields: [:originalhash], id: entry.hash_id).originalhash
            line = line + ':' + Hashes.first(fields: [:plaintext], id: entry.hash_id, cracked: 1).plaintext
            @filecontents.add(line)
          elsif params[:type] == 'uncracked' and not Hashes.first(fields: [:cracked], id: entry.hash_id).cracked
            if entry.username.nil? # no username
              line = ''
            else
              line = entry.username + ':'
            end
            line = line + Hashes.first(fields: [:originalhash], id: entry.hash_id).originalhash
            @filecontents.add(line)
          end
        end
      else
        @filecontents = Set.new
        @hashfiles_ids = Hashfiles.all(fields: [:id], customer_id: params[:customer_id]).each do |hashfile|
          Hashfilehashes.all(fields: [:id], hashfile_id: hashfile.id).each do |entry|
            if params[:type] == 'cracked' and Hashes.first(fields: [:cracked], id: entry.hash_id).cracked
              if entry.username.nil? # no username
                line = ''
              else
                line = entry.username + ':'
              end
              line = line + Hashes.first(fields: [:originalhash], id: entry.hash_id).originalhash
              line = line + ':' + Hashes.first(fields: [:plaintext], id: entry.hash_id, cracked: 1).plaintext
              @filecontents.add(line)
            elsif params[:type] == 'uncracked' and not Hashes.first(fields: [:cracked], id: entry.hash_id).cracked
              if entry.username.nil? # no username
                line = ''
              else
                line = entry.username + ':'
              end
              line = line + Hashes.first(fields: [:originalhash], id: entry.hash_id).originalhash
              @filecontents.add(line)
            end
          end    
        end
      end
    else
      @filecontents = Set.new
      @hashfiles_ids = Hashfiles.all(fields: [:id]).each do |hashfile|
        Hashfilehashes.all(fields: [:id], hashfile_id: hashfile.id).each do |entry|
          if params[:type] == 'cracked' and Hashes.first(fields: [:cracked], id: entry.hash_id).cracked
            if entry.username.nil? # no username
              line = ''
            else
              line = entry.username + ':'
            end
            line = line + Hashes.first(fields: [:originalhash], id: entry.hash_id).originalhash
            line = line + ':' + Hashes.first(fields: [:plaintext], id: entry.hash_id, cracked: 1).plaintext
            @filecontents.add(line)
          elsif params[:type] == 'uncracked' and not Hashes.first(fields: [:cracked], id: entry.hash_id).cracked
            if entry.username.nil? # no username
              line = ''
            else
              line = entry.username + ':'
            end
            line = line + Hashes.first(fields: [:originalhash], id: entry.hash_id).originalhash
            @filecontents.add(line)
          end
        end
      end
    end
  
    # Write temp output file
    if params[:customer_id] && !params[:customer_id].empty?
      if params[:hashfile_id] && !params[:hashfile_id].nil?
        file_name = "found_#{params[:customer_id]}_#{params[:hashfile_id]}.txt" if params[:type] == 'cracked'
        file_name = "left_#{params[:customer_id]}_#{params[:hashfile_id]}.txt" if params[:type] == 'uncracked'
      else
        file_name = "found_#{params[:customer_id]}.txt" if params[:type] == 'cracked'
        file_name = "left_#{params[:customer_id]}.txt" if params[:type] == 'uncracked'
      end
    else
      file_name = 'found_all.txt' if params[:type] == 'cracked'
      file_name = 'left_all.txt' if params[:type] == 'uncracked'
    end
  
    file_name = 'control/outfiles/' + file_name
  
    File.open(file_name, 'w') do |f|
      @filecontents.each do |entry|
        f.puts entry
      end
    end
  
    send_file file_name, filename: file_name, type: 'Application/octet-stream'
  end
end
