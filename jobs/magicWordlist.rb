def generateMagicWordlist
  # Get list of all wordlists
  # TODO add --parallel #
  shell_cmd = 'sort -u '
  @wordlists = Wordlists.all
  @wordlists.each do |entry|
    shell_cmd = shell_cmd + entry.path.to_s + ' '
  end
  shell_cmd = shell_cmd + '-o /tmp/MagicWordlist.txt' # We move to temp to prevent wordlist importer from accidentally loading the magic wordlist too early
  p "shell_cmd: " + shell_cmd
  system(shell_cmd)

  shell_mv_cmd = 'mv /tmp/MagicWordlist.txt control/wordlists/MagicWordList.txt'
  system(shell_mv_cmd)
end

class MagicWordlist
  @queue = :management

  def self.perform()
    puts "Magic Wordlists Class"

    has_magic_wordlist = Wordlists.first(name: "MagicWordList.txt")
    if has_magic_wordlist
      p 'LAST UPDATED: ' + has_magic_wordlist.lastupdated.to_s
      # Has magic wordlist already, need to check if its outdated
      @wordlists = Wordlists.all(:lastupdated.gt => has_magic_wordlist.lastupdated)
      if @wordlists.size > 0
        p 'Our magic wordlist is out of date'
        shell_cmd = 'sort -u control/wordlists/MagicWordList.txt '
        @wordlists.each do |entry|
          shell_cmd = shell_cmd + entry.path.to_s + ' '
        end
        shell_cmd = shell_cmd + '-o /tmp/MagicWordlist.txt'
        p 'SHELL CMD: ' + shell_cmd
        system(shell_cmd)

        p 'Replace old MagicWordlist with new file'
        shell_mv_cmd = 'mv /tmp/MagicWordlist.txt control/wordlists/MagicWordList.txt'
        system(shell_mv_cmd)

        p 'Update DB'

        # Finding Size
        size = File.foreach(has_magic_wordlist.path).inject(0) { |c| c + 1 }

        has_magic_wordlist.lastupdated = Time.now
        has_magic_wordlist.size = size
        has_magic_wordlist.save       

      else
        p 'Our magic wordlist is current.'
      end
    else
      # Need to generate the Magic Wordlist
      generateMagicWordlist
    end
  end
end
