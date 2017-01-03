require 'rubygems'
require 'sinatra'
require './model/master'

def detectedHashFormat(hash)
  # Detect if pwdump file format
  if hash =~ /^[^:]+:\d+:.*:.*:.*:.*:$/
    return 'pwdump'
  # Detect if shadow
  elsif hash =~ /^.*:.*:\d*:\d*:\d*:\d*:\d*:\d*:$/
    return 'shadow'
  elsif hash =~ /^.*:(\$NT\$)?\w{32}:.*:.*:/ # old version of dsusers
    return 'dsusers'
  elsif hash =~ /^.*:\w{32}$/
    return 'dsusers'
  elsif hash =~ /^\w{32}$/
    return 'ntlm_only'
  else
    return 'File Format or Hash not supported'
  end
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
 
    @hash_id = Hashes.first(fields: [:id], originalhash: lm_hash_0, hashtype: '3000')
    if @hash_id.nil?
      hashes_lm0 = Hashes.new
      hashes_lm0.originalhash = lm_hash_0
      hashes_lm0.hashtype = '3000'
      hashes_lm0.cracked = false
      hashes_lm0.save

      @hash_id = Hashes.first(fields: [:id], originalhash: lm_hash_0, hashtype: '3000')
    end

    hashfileHashes_0 = Hashfilehashes.new
    hashfileHashes_0.hash_id = hash_id.id.to_i
    hashfileHashes_0.username = data[0]
    hashfileHashes_0.hashfile_id = hashfile_id
    hashfileHashes_0.save

    @hash_id = Hashes.first(fields: [:id], originalhash: lm_hash_1, hashtype: '3000')
    if @hash_id.nil?
      hashes_lm1 = Hashes.new
      hashes_lm1.originalhash = lm_hash_1
      hashes_lm1.hashtype = '3000'
      hashes_lm1.cracked = false
      hashes_lm1.save

      @hash_id = Hashes.first(fields: [:id], originalhash: lm_hash_1, hashtype: '3000')
    end

    hashfileHashes_1 = Hashfilehashes.new
    hashfileHashes_1.hash_id = @hash_id.id.to_i
    hashfileHashes_1.username = data[0]
    hashfileHashes_1.hashfile_id = hashfile_id
    hashfileHashes_1.save
  end

  # if hashtype is ntlm
  if type == '1000'
    @hash_id = Hashes.first(fields: [:id], originalhash: data[3], hashtype: '1000')
    if @hash_id.nil?
      hashes_ntlm = Hashes.new
      hashes_ntlm.originalhash = data[3]
      hashes_ntlm.hashtype = '1000'
      hashes_ntlm.cracked = false
      hashes_ntlm.save

      @hash_id = Hashes.first(fields: [:id], originalhash: data[3], hashtype: '1000')
    end

    hashfileHashes_ntlm = Hashfilehashes.new
    hashfileHashes_ntlm.hash_id = @hash_id.id.to_i
    hashfileHashes_ntlm.username = data[0]
    hashfileHashes_ntlm.hashfile_id = hashfile_id
    hashfileHashes_ntlm.save
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
    hashes = Hashes.new
    hashes.originalhash = data[1]
    hashes.hashtype = type
    hashes.cracked = false
    hashes.save

     @hash_id = Hashes.first(fields: [:id], originalhash: data[1], hashtype: type)
  end

  hashfileHashes = Hashfilehashes.new
  hashfileHashes.hash_id = @hash_id.id.to_i
  hashfileHashes.username = data[0]
  hashfileHashes.hashfile_id = hashfile_id
  hashfileHashes.save
end

def importDsusers(hash, hashfile_id, type)
  data = hash.split(':')
  if data[1] =~ /NT/
    data[1] = data[1].to_s.split('$')[2]
    type = '3000'
  end

  @hash_id = Hashes.first(fields: [:id], originalhash: data[1], hashtype: type)
  if @hash_id.nil?
    hashes = Hashes.new
    hashes.originalhash = data[1]
    hashes.hashtype = type
    hashes.cracked = false
    hashes.save

     @hash_id = Hashes.first(fields: [:id], originalhash: data[1], hashtype: type)
  end

  hashfileHashes = Hashfilehashes.new
  hashfileHashes.hash_id = @hash_id.id.to_i
  hashfileHashes.username = data[0]
  hashfileHashes.hashfile_id = hashfile_id
  hashfileHashes.save
end

def importRaw(hash, hashfile_id, type)
  if type == '3000'
    # import LM
    lm_hashes = hash.scan(/.{16}/)
    lm_hash_0 = lm_hashes[0].downcase
    lm_hash_1 = lm_hashes[1].downcase

    @hash_id = Hashes.first(fields: [:id], originalhash: lm_hash_0, hashtype: '3000')
    if @hash_id.nil?
      hashes_lm0 = Hashes.new
      hashes_lm0.originalhash = lm_hash_0
      hashes_lm0.hashtype = '3000'
      hashes_lm0.cracked = false
      hashes_lm0.save

      @hash_id = Hashes.first(fields: [:id], originalhash: lm_hash_0, hashtype: '3000')
    end

    hashfileHashes_0 = Hashfilehashes.new
    hashfileHashes_0.hash_id = @hash_id.id.to_i
    hashfileHashes_0.hashfile_id = hashfile_id
    hashfileHashes_0.save

    @hash_id = Hashes.first(fields: [:id], originalhash: lm_hash_1, hashtype: '3000')
    if @hash_id.nil?
      hashes_lm1 = Hashes.new
      hashes_lm1.originalhash = lm_hash_1
      hashes_lm1.hashtype = '3000'
      hashes_lm1.cracked = false
      hashes_lm1.save

      @hash_id = Hashes.first(fields: [:id], originalhash: lm_hash_1, hashtype: '3000')
    end

    hashfileHashes_1 = Hashfilehashes.new
    hashfileHashes_1.hash_id = @hash_id.id.to_i
    hashfileHashes_1.hashfile_id = hashfile_id
    hashfileHashes_1.save

  elsif type == '5500'
    # import NetNTLMv1
    fields = hash.split(':')
    originalhash = fields[3].to_s.downcase + ':' + fields[4].to_s.downcase + ':' + fields[5].to_s.downcase

    @hash_id = Hashes.first(fields: [:id], originalhash: originalhash, hashtype: '5500')
    if @hash_id.nil?
      hashes = Hashes.new
      hashes.originalhash = originalhash
      hashes.hashtype = '5500'
      hashes.cracked = false
      hashes.save

      @hash_id = Hashes.first(fields: [:id], originalhash: originalhash, hashtype: '5500')
    end

    hashfileHashes = Hashfilehashes.new
    hashfileHashes.hash_id = @hash_id.id.to_i
    hashfileHashes.username = fields[0]
    hashfileHashes.hashfile_id = hashfile_id
    hashfileHashes.save

  elsif type == '5600'
    # We need to include full hash (username, salt, computername)
    # import NetNTLMv2
    fields = hash.split(':')

    @hash_id = Hashes.first(fields: [:id], originalhash: hash, hashtype: '5600')
    if @hash_id.nil?
      hashes = Hashes.new
      hashes.originalhash = hash
      hashes.hashtype = '5600'
      hashes.cracked = false
      hashes.save

      @hash_id = Hashes.first(fields: [:id], originalhash: hash, hashtype: '5600')
    end

    hashfileHashes = Hashfilehashes.new
    hashfileHashes.hash_id = @hash_id.id.to_i
    hashfileHashes.username = fields[0]
    hashfileHashes.hashfile_id = hashfile_id
    hashfileHashes.save

  else
    @hash_id = Hashes.first(fields: [:id], originalhash: hash, hashtype: type)
    if @hash_id.nil?
      hashes = Hashes.new
      hashes.originalhash = hash
      hashes.hashtype = type
      hashes.cracked = false
      hashes.save
    
      @hash_id = Hashes.first(fields: [:id], originalhash: hash, hashtype: type)
    end

    hashfileHashes = Hashfilehashes.new
    hashfileHashes.hash_id = @hash_id.id.to_i
    hashfileHashes.hashfile_id = hashfile_id
    hashfileHashes.save

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
    if file_type == 'pwdump'
      importPwdump(entry.chomp, hashfile_id, hashtype)
    elsif file_type == 'shadow'
      importShadow(entry.chomp, hashfile_id, hashtype)
    elsif file_type == 'raw'
      importRaw(entry.chomp, hashfile_id, hashtype)
    elsif file_type == 'dsusers'
      importDsusers(entry.chomp, hashfile_id, hashtype)
    else
      return 'Unsupported hash format detected'
    end
  end
end

def detectHashfileType(hash_file)
  @file_types = []
  File.readlines(hash_file).each do |entry|
    if detectedHashFormat(entry.chomp) == 'pwdump'
      @file_types.push('pwdump') unless @file_types.include?('pwdump')
    elsif detectedHashFormat(entry.chomp) == 'shadow'
      @file_types.push('shadow') unless @file_types.include?('shadow')
    elsif detectedHashFormat(entry.chomp) == 'dsusers'
      @file_types.push('dsusers') unless @file_types.include?('dsusers')
    else
      @file_types.push('raw') unless @file_types.include?('raw')
    end
  end

  @file_types
end

def detectHashType(hash_file, file_type)
  @hashtypes = []
  File.readlines(hash_file).each do |entry|
    if file_type == 'pwdump'
      elements = entry.split(':')
      @modes = getMode(elements[2])
      @modes.each do |mode|
        @hashtypes.push(mode) unless @hashtypes.include?(mode) # LM
      end
      @modes = getMode(elements[3])
      @modes.each do |mode|
        @hashtypes.push(mode) unless @hashtypes.include?(mode) # NTLM
      end
    elsif file_type == 'shadow' || file_type == 'dsusers'
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
