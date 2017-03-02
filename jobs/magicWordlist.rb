def generateMagicWordlist
  # Get list of all plaintext passwords and save it to a file
  @plaintexts = Hashes.all(fields: [:plaintext], cracked: 1, unique: true, order: [:plaintext.asc])
  file_name = 'control/tmp/plaintext.txt'

  File.open(file_name, 'w') do |f|
    @plaintexts.each do |entry|
      f.puts entry.plaintext
    end
  end
   
  # Get list of all wordlists
  # TODO add --parallel #
  shell_cmd = 'sort -u control/tmp/plaintext.txt '
  @wordlists = Wordlists.all
  @wordlists.each do |entry|
    shell_cmd = shell_cmd + entry.path.to_s + ' '
  end
  shell_cmd = shell_cmd + '-o control/tmp/MagicWordlist.txt' # We move to temp to prevent wordlist importer from accidentally loading the magic wordlist too early
  p "shell_cmd: " + shell_cmd
  system(shell_cmd)

  shell_mv_cmd = 'mv control/tmp/MagicWordlist.txt control/wordlists/MagicWordList.txt'
  system(shell_mv_cmd)

  # Remove plaintext list
  File.delete('control/tmp/plaintext.txt')
end

class MagicWordlist
  @queue = :management

  def self.perform()
    puts "Magic Wordlists Class"
    require './helpers/status.rb'
    unless isBusy? # only run if kraken is not running to prevent the swapping/deletion of a wordlist mid crack

      has_magic_wordlist = Wordlists.first(name: "MagicWordList.txt")
      if has_magic_wordlist
        p 'LAST UPDATED: ' + has_magic_wordlist.lastupdated.to_s
        # Has magic wordlist already, need to check if its outdated
        @wordlists = Wordlists.all(:lastupdated.gt => has_magic_wordlist.lastupdated)
        @plaintexts = Hashes.all(:lastupdated.gt => has_magic_wordlist.lastupdated)
        if @wordlists.size > 0 || @plaintexts.size > 0
  
          file_name = '/tmp/plaintext.txt'
  
          File.open(file_name, 'w') do |f|
            @plaintexts.each do |entry|
              f.puts entry.plaintext
            end
          end
  
          p 'Our magic wordlist is out of date'
          shell_cmd = 'sort -u control/wordlists/MagicWordList.txt '
          @wordlists.each do |entry|
            shell_cmd = shell_cmd + entry.path.to_s + ' '
          end
          shell_cmd = shell_cmd + '-o control/tmp/MagicWordlist.txt'
          p 'SHELL CMD: ' + shell_cmd
          system(shell_cmd)

          p 'Replace old MagicWordlist with new file'
          shell_mv_cmd = 'mv control/tmp/MagicWordlist.txt control/wordlists/MagicWordList.txt'
          system(shell_mv_cmd)

          p 'Update DB'

          # Finding Size
          size = File.foreach(has_magic_wordlist.path).inject(0) { |c| c + 1 }

          has_magic_wordlist.lastupdated = Time.now
          has_magic_wordlist.size = size
          has_magic_wordlist.save       

          # Remove plaintext list
          File.delete('control/tmp/plaintext.txt')

        else
          p 'Our magic wordlist is current.'
        end
      else
        # Need to generate the Magic Wordlist
        generateMagicWordlist
      end
    end
    puts "Magic Wordlist Class() - Done"
  end
end
