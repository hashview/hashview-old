# encoding: utf-8
#require './model/master'
#def detectedHashFormat(hash)
#  # Detect if pwdump file format
#  if hash =~ /^[^:]+:\d+:.*:.*:.*:.*:$/
#    return 'pwdump'
#  # Detect if shadow
#  elsif hash =~ /^.*:.*:\d*:\d*:\d*:\d*:\d*:\d*:$/
#    return 'shadow'
#  elsif hash =~ /^.*:(\$NT\$)?\w{32}:.*:.*:/ # old version of dsusers
#    return 'dsusers'
#  elsif hash =~ /^.*:\w{32}$/
#    return 'dsusers'
#  elsif hash =~ /^.*:\w.*/
#    return 'generic'
#  elsif hash =~ /^\w{32}$/
#    return 'ntlm_only'
#  elsif hash =~ /.*:\d*:\w{32}:\w{32}$/
#    return 'smart hashdump'
#  else
#    return 'File Format or Hash not supported'
#  end
#end

def addHash(hash, hashtype)
  entry = Hashes.new
  entry.originalhash = hash
  entry.hashtype = hashtype
  entry.cracked = false
  entry.save
end

def updateHashfileHashes(hash_id, username, hashfile_id)
  entry = Hashfilehashes.new
  entry.hash_id = hash_id
  entry.username = username
  entry.hashfile_id = hashfile_id
  entry.save
end

def importPwdump(hash, hashfile_id, type)
  data = hash.split(':')
  return if machineAcct?(data[0])
  return if data[2].nil?
  return if data[3].nil?

  # if hashtype is lm
  if type == '3000'
    # import LM
    lm_hashes = data[2].scan(/.{16}/)
    lm_hash_0 = lm_hashes[0].downcase
    lm_hash_1 = lm_hashes[1].downcase
 
    @hash_id = Hashes.first(fields: [:id], originalhash: lm_hash_0, hashtype: type)
    if @hash_id.nil?
      addHash(lm_hash_0, type)
      @hash_id = Hashes.first(fields: [:id], originalhash: lm_hash_0, hashtype: type)
    end

    updateHashfileHashes(@hash_id.id.to_i, data[0], hashfile_id)

    @hash_id = Hashes.first(fields: [:id], originalhash: lm_hash_1, hashtype: type)
    if @hash_id.nil?
      addHash(lm_hash_1, type)
      @hash_id = Hashes.first(fields: [:id], originalhash: lm_hash_1, hashtype: type)
    end

    updateHashfileHashes(@hash_id.id.to_i, data[0], hashfile_id)
  end

  # if hashtype is ntlm
  if type == '1000'
    @hash_id = Hashes.first(fields: [:id], originalhash: data[3], hashtype: type)
    if @hash_id.nil?
      addHash(data[3], type)
      @hash_id = Hashes.first(fields: [:id], originalhash: data[3], hashtype: type)
    end

    updateHashfileHashes(@hash_id.id.to_i, data[0], hashfile_id)
  end
end

def machineAcct?(username)
  if username =~ /\$/
    return true
  else
    return false
  end
end

def importShadow(hash, hashfile_id, type)
  # This parser needs some work
  data = hash.split(':')
  @hash_id = Hashes.first(fields: [:id], originalhash: data[1], hashtype: type)
  if @hash_id.nil?
    addHash(data[1], type)
    @hash_id = Hashes.first(fields: [:id], originalhash: data[1], hashtype: type)
  end

  updateHashfileHashes(@hash_id.id.to_i, data[0], hashfile_id)
end

def importDsusers(hash, hashfile_id, type)
  data = hash.split(':')
  if data[1] =~ /NT/
    data[1] = data[1].to_s.split('$')[2]
    type = '3000'
  end

  @hash_id = Hashes.first(fields: [:id], originalhash: data[1], hashtype: type)
  if @hash_id.nil?
    addHash(data[1], type)
    @hash_id = Hashes.first(fields: [:id], originalhash: data[1], hashtype: type)
  end

  updateHashfileHashes(@hash_id.id.to_i, data[0], hashfile_id)
end

def importUserHash(hash, hashfile_id, type)
  data = hash.split(':')
  @hash_id = Hashes.first(fields: [:id], originalhash: data[1], hashtype: type)
  if @hash_id.nil?
    addHash(data[1], type)
    @hash_id = Hashes.first(fields: [:id], originalhash: data[1], hashtype: type)
  end

  updateHashfileHashes(@hash_id.id.to_i, data[0], hashfile_id)
end

def importHashOnly(hash, hashfile_id, type)
  if type == '3000'
    # import LM
    lm_hashes = hash.scan(/.{16}/)
    lm_hash_0 = lm_hashes[0].downcase
    lm_hash_1 = lm_hashes[1].downcase

    @hash_id = Hashes.first(fields: [:id], originalhash: lm_hash_0, hashtype: type)
    if @hash_id.nil?
      addHash(lm_hash_0, type)
      @hash_id = Hashes.first(fields: [:id], originalhash: lm_hash_0, hashtype: type)
    end

    updateHashfileHashes(@hash_id.id.to_i, 'NULL', hashfile_id)

    @hash_id = Hashes.first(fields: [:id], originalhash: lm_hash_1, hashtype: type)
    if @hash_id.nil?
      addHash(lm_hash_1, type)
      @hash_id = Hashes.first(fields: [:id], originalhash: lm_hash_1, hashtype: '3000')
    end

    updateHashfileHashes(@hash_id.id.to_i, 'NULL', hashfile_id)

  elsif type == '5500'
    # import NetNTLMv1
    fields = hash.split(':')
    originalhash = fields[3].to_s.downcase + ':' + fields[4].to_s.downcase + ':' + fields[5].to_s.downcase

    @hash_id = Hashes.first(fields: [:id], originalhash: originalhash, hashtype: type)
    if @hash_id.nil?
      addHash(originalhash, type)
      @hash_id = Hashes.first(fields: [:id], originalhash: originalhash, hashtype: type)
    end

    updateHashfileHashes(@hash_id.id.to_i, fields[0], hashfile_id)

  elsif type == '5600'
    # We need to include full hash (username, salt, computername)
    # import NetNTLMv2
    fields = hash.split(':')

    @hash_id = Hashes.first(fields: [:id], originalhash: hash, hashtype: type)
    if @hash_id.nil?
      addHash(hash, type)
      @hash_id = Hashes.first(fields: [:id], originalhash: hash, hashtype: type)
    end
  
    updateHashfileHashes(@hash_id.id.to_i, fields[0], hashfile_id)

  else
    @hash_id = Hashes.first(fields: [:id], originalhash: hash, hashtype: type)
    if @hash_id.nil?
      addHash(hash, type)
      @hash_id = Hashes.first(fields: [:id], originalhash: hash, hashtype: type)
    end
   
    updateHashfileHashes(@hash_id.id.to_i, 'NULL', hashfile_id)

  end
end

def getMode(hash)
  @modes = []
  if hash =~ /^\w{32}$/
    @modes.push('1000') # NTLM
    @modes.push('3000') # LM (in pwdump format)
    @modes.push('0')	# MD5
  elsif hash =~ %r{\$NT\$\w{32}} # NTLM
    @modes.push('1000')
  elsif hash =~ /^[a-f0-9]{40}(:.+)?$/
    @modes.push('100')  # SHA-1
  elsif hash =~ %r{^\$1\$[\.\/0-9A-Za-z]{0,8}\$[\.\/0-9A-Za-z]{22}$}
    @modes.push('500') 	# md5crypt
  elsif hash =~ /^[0-9A-Za-z]{16}$/
    @modes.push('3000') # LM
  elsif hash =~ /\$\d+\$.{53}$/
    @modes.push('3200')	# bcrypt, Blowfish(OpenBSD)
  elsif hash =~ %r{^\$5\$rounds=\d+\$[\.\/0-9A-Za-z]{0,16}\$[\.\/0-9A-Za-z]{0,43}$}
    @modes.push('7400')	# sha256crypt, SHA256(Unix)
  elsif hash =~ %r{^\$6\$[\.\/0-9A-Za-z]{4,9}\$[\.\/0-9A-Za-z]{86}$}
    @modes.push('1800')	# sha512crypt, SHA512(Unix)
  elsif hash =~ %r{^[\.\/0-9A-Za-z]{13}$}
    @modes.push('1500')	# descrypt, DES(Unix), Traditional DES
  elsif hash =~ /^[^\\\/:*?"<>|]{1,20}[:]{2,3}[^\\\/:*?"<>|]{1,20}?:[a-f0-9]{48}:[a-f0-9]{48}:[a-f0-9]{16}$/i
    @modes.push('5500')	# NetNTLMv1-VANILLA / NetNTLMv1+ESS
  elsif hash =~ /^[^\\\/:*?"<>|]{1,20}\\?[^\\\/:*?"<>|]{1,20}[:]{2,3}[^\\\/:*?"<>|]{1,20}:?[^\\\/:*?"<>|]{1,20}:[a-f0-9]{32}:[a-f0-9]+$/i
    @modes.push('5600')	# NetNTLMv2
  end

  @modes
end

def modeToFriendly(mode)
  return 'MD5' if mode == '0'
  return 'NTLM' if mode == '1000'
  return 'LM' if mode == '3000'
  return 'SHA-1' if mode == '100'
  return 'md5crypt' if mode == '500'
  return 'bcrypt' if mode == '3200'
  return 'sha256crypt' if mode == '7400'
  return 'sha512crypt' if mode == '1800'
  return 'descrypt' if mode == '1500'
  return 'NetNTLMv1' if mode == '5500'
  return 'NetNTLMv2' if mode == '5600'
  return 'unknown'
end

def friendlyToMode(friendly)
  return '0' if friendly == 'MD5'
  return '1000' if friendly == 'NTLM'
  return '3000' if friendly == 'LM'
  return '100' if friendly == 'SHA-1'
  return '500' if friendly == 'md5crypt'
  return '3200' if friendly == 'bcrypt'
  return '7400' if friendly == 'sha512crypt'
  return '1800' if friendly == 'sha256crypt'
  return '1500' if friendly == 'descrypt'
  return '5500' if friendly == 'NetNTLMv1'
  return '5600' if friendly == 'NetNTLMv2'
end

def importHash(hash_file, hashfile_id, file_type, hashtype)
  hash_file.each do |entry|
    entry = entry.gsub(/\s+/, '') # remove all spaces
    if file_type == 'pwdump' or file_type == 'smart hashdump' 
      importPwdump(entry.chomp, hashfile_id, hashtype) #because the format is the same aside from the trailing ::
    elsif file_type == 'shadow'
      importShadow(entry.chomp, hashfile_id, hashtype)
    elsif file_type == 'hash_only'
      importHashOnly(entry.chomp, hashfile_id, hashtype)
    elsif file_type == 'dsusers'
      importDsusers(entry.chomp, hashfile_id, hashtype)
    elsif file_type == 'user_hash'
      importUserHash(entry.chomp, hashfile_id, hashtype)
    else
      return 'Unsupported hash format detected'
    end
  end
end

#def detectHashfileType(hash_file)
#  @file_types = []
#  File.readlines(hash_file).each do |entry|
#    entry = entry.gsub(/\s+/, "") # remove all spaces
#    if detectedHashFormat(entry.chomp) == 'pwdump'
#      @file_types.push('pwdump') unless @file_types.include?('pwdump')
#    elsif detectedHashFormat(entry.chomp) == 'shadow'
#      @file_types.push('shadow') unless @file_types.include?('shadow')
#    elsif detectedHashFormat(entry.chomp) == 'dsusers'
#      @file_types.push('dsusers') unless @file_types.include?('dsusers')
#    elsif detectedHashFormat(entry.chomp) == 'generic'
#      @file_types.push('generic') unless @file_types.include?('generic')
#    elsif detectedHashFormat(entry.chomp) == 'smart hashdump'
#      @file_types.push('smart hashdump') unless @file_types.include?('smart hashdump')
#    else
#      @file_types.push('raw') unless @file_types.include?('raw')
#    end
#  end

  @file_types
end

def detectHashType(hash_file, file_type)
  @hashtypes = []
  File.readlines(hash_file).each do |entry|
    entry = entry.gsub(/\s+/, "") # remove all spaces
    if file_type == 'pwdump' or file_type == 'smart_hashdump'
      elements = entry.split(':')
      @modes = getMode(elements[2])
      @modes.each do |mode|
        @hashtypes.push(mode) unless @hashtypes.include?(mode) # LM
      end
      @modes = getMode(elements[3])
      @modes.each do |mode|
        @hashtypes.push(mode) unless @hashtypes.include?(mode) # NTLM
      end
    elsif file_type == 'shadow' || file_type == 'dsusers' || file_type == 'user_hash'
      elements = entry.split(':')
      @modes = getMode(elements[1])
      @modes.each do |mode|
        @hashtypes.push(mode) unless @hashtypes.include?(mode)
      end
    else
      @modes = getMode(entry)
      @modes.each do |mode|
        @hashtypes.push(mode) unless @hashtypes.include?(mode)
      end
    end
  end
  @hashtypes
end
