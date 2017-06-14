class FileChecksum
  @queue = :management
  def self.perform(type, id)

    if type == 'rules'
      rules_file = Rules.first(id: id)
      cmd = rules_file.path
      checksum = `sha256sum "#{cmd}"`
      rules_file.checksum = checksum
      rules_file.save
    elsif type == 'wordlist'
      wordlists = Wordlists.first(id: id)
      cmd = wordlists.path
      checksum = `sha256sum "#{cmd}"`
      wordlists.checksum = checksum
      wordlists.save
    end
  end
end
