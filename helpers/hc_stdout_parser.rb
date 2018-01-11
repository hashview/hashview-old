# encoding: utf-8
helpers do
  def hashcatParser(file)
    status = {}
    begin
      File.open(file).each_line do |line|
        if line.start_with?('Time.Started.')
          status['Time_Started'] = line.split(': ')[-1].strip
        elsif line.start_with?('Time.Estimated.')
          status['Time_Estimated'] = line.split(': ')[-1].strip
        elsif line.start_with?('Recovered.')
          status['Recovered'] = line.split(': ')[-1].strip
        elsif line.start_with?('Input.Mode.')
          status['Input_Mode'] = line.split(': ')[-1].strip
        elsif line.start_with?('Guess_Mask')
          status['Guess_Mask'] = line.split(': ')[-1].strip
        elsif line.start_with?('Speed.Dev.')
          item = line.split(': ')
          gpu = item[0].gsub!('Speed.Dev.', 'Speed Dev ').gsub!('.', '')
          status[gpu] = line.split(': ')[-1].strip
        elsif line.start_with?('HWMon.Dev.')
          item = line.split('.: ')
          gpu = item[0].gsub!('HWMon.Dev.', 'HWMon Dev ').gsub!('.', '')
          status[gpu] = line.split('.: ')[-1].strip
        end
      end
    rescue SystemCallError => e
      puts e
    end
    status
  end
end
