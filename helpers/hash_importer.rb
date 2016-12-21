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
  #elsif hash =~ /^.*:(\$NT\$)?\w{32}:.*:.*:/ # old version of dsusers
  elsif hash =~ /^.*:\w{32}$/
    return 'dsusers'
  elsif hash =~ /^\w{32}$/
    return 'ntlm_only'
  else
    return 'File Format or Hash not supported'
  end
end

def importPwdump(hash, customer_id, hashfile_id, type)
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
 
    hash_id = Hashes.first(fields: [:id], originalhash: lm_hash_0, hashtype: '3000')[0].to_i
    if hash_id == 0
      p 'DEBUG: this is a new entry ' + hash_id.to_s
      hashes_lm0 = Hashes.new
      hashes_lm0.originalhash = lm_hash_0
      hashes_lm0.hashtype = '3000'
      hashes_lm0.cracked = false
      hashes_lm0.save

      hash_id = Hashes.first(fields: [:id], originalhash: lm_hash_0, hashtype: '3000')[0].to_i
    else
     p 'DEBUG: This entry already exists ' + hash_id.to_s
    end

    hashfileHashes_0 = Hashfilehashes.new
    hashfileHashes_0.hash_id = hash_id
    hashfileHashes_0.username = data[0]
    hashfileHashes_0.hashfile_id = hashfile_id
    hashfileHashes_0.save

    hash_id = Hashes.first(fields: [:id], originalhash: lm_hash_1, hashtype: '3000')[0].to_i
    if hash_id == 0
      p 'DEBUG: this is a new entry ' + hash_id.to_s
      hashes_lm1 = Hashes.new
      hashes_lm1.originalhash = lm_hash_1
      hashes_lm1.hashtype = '3000'
      hashes_lm1.cracked = false
      hashes_lm1.save

      hash_id = Hashes.first(fields: [:id], originalhash: lm_hash_1, hashtype: '3000')[0].to_i
    else
     p 'DEBUG: This entry already exists ' + hash_id.to_s
    end

    hashfileHashes_1 = Hashfilehashes.new
    hashfileHashes_1.hash_id = hash_id
    hashfileHashes_1.username = data[0]
    hashfileHashes_1.hashfile_id = hashfile_id
    hashfileHashes_1.save

  end

  # if hashtype is ntlm
  if type == '1000'
    hash_id = Hashes.first(fields: [:id], originalhash: data[3], hashtype: '1000')[0]
    p 'debug hash_id class: ' + hash_id.class.to_s
    if hash_id == 0
      p 'DEBUG: this is a new entry ' + hash_id.to_s
      hashes_ntlm = Hashes.new
      hashes_ntlm.originalhash = data[3]
      hashes_ntlm.hashtype = '3000'
      hashes_ntlm.cracked = false
      hashes_ntlm.save

      hash_id = Hashes.first(fields: [:id], originalhash: data[3], hashtype: '1000')[0]
    else
      p 'DEBUG: This entry already exists ' + hash_id.to_s
    end
    p 'DEBUG: hash_id: ' + hash_id.to_s

    p 'DEBUG: New entry should be created'
    hashfileHashes_ntlm = Hashfilehashes.new
    hashfileHashes_ntlm.hash_id = hash_id.to_i
    hashfileHashes_ntlm.username = data[0]
    hashfileHashes_ntlm.hashfile_id = hashfile_id
    hashfileHashes_ntlm.save
    p 'Debug: new Entry created'

  end
end

def machineAcct?(username)
  if username =~ /\$/
    return true
  else
    return false
  end
end

def importShadow(hash, customer_id, hashfile_id, type)
  data = hash.split(':')
  target = Targets.new
  target.username = data[0]
  target.originalhash = data[1]
  target.hashtype = type
  target.hashfile_id = hashfile_id
  target.customer_id = customer_id
  target.cracked = false
  target.save
end

def importDsusers(hash, customer_id, hashfile_id, type)
  data = hash.split(':')
  target = Targets.new
  target.username = data[0]
  if type == '1000' # import NTLM
    target.hashtype = '1000'
  #  lm_hash = data[1].split('$')
  #  target.originalhash = lm_hash[2]
    target.originalhash = data[1]
  end
  if type == '3000' # import LM
    target.hashtype = '3000'
    target.originalhash = data[1]
  end
  target.hashfile_id = hashfile_id
  target.customer_id = customer_id
  target.cracked = false
  target.save
end

def importRaw(hash, customer_id, hashfile_id, type)
  if type == '3000'
    # import LM
    lm_hashes = hash.scan(/.{16}/)

    target_lm1 = Targets.new
    target_lm1.originalhash = lm_hashes[0].downcase
    target_lm1.hashtype = '3000'
    target_lm1.hashfile_id = hashfile_id
    target_lm1.customer_id = customer_id
    target_lm1.cracked = false
    target_lm1.save

    target_lm2 = Targets.new
    target_lm2.originalhash = lm_hashes[1].downcase
    target_lm2.hashtype = '3000'
    target_lm2.hashfile_id = hashfile_id
    target_lm2.customer_id = customer_id
    target_lm2.cracked = false
    target_lm2.save

  elsif type == '5500'
    # import NetNTLMv1
    fields = hash.split(':')
    target_NetNTLMv1 = Targets.new
    target_NetNTLMv1.username = fields[0]
    target_NetNTLMv1.originalhash = fields[3].to_s.downcase + ':' + fields[4].to_s.downcase + ':' + fields[5].to_s.downcase
    target_NetNTLMv1.hashtype = '5500'
    target_NetNTLMv1.hashfile_id = hashfile_id
    target_NetNTLMv1.customer_id = customer_id
    target_NetNTLMv1.cracked = false
    target_NetNTLMv1.save    

  elsif type == '5600'
    # import NetNTLMv2
    fields = hash.split(':')
    target_NetNTLMv2 = Targets.new
    target_NetNTLMv2.username = fields[0]
    target_NetNTLMv2.originalhash = hash # looks like we need full hash including username, salt, computername
    target_NetNTLMv2.hashtype = '5600'
    target_NetNTLMv2.hashfile_id = hashfile_id
    target_NetNTLMv2.customer_id = customer_id
    target_NetNTLMv2.cracked = false
    target_NetNTLMv2.save

  else
    target_raw = Targets.new
    target_raw.originalhash = hash
    target_raw.hashtype = type
    target_raw.hashfile_id = hashfile_id
    target_raw.customer_id = customer_id
    target_raw.cracked = false
    target_raw.save
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

def importHash(hash_file, customer_id, hashfile_id, file_type, hashtype)
  hash_file.each do |entry|
    if file_type == 'pwdump'
      importPwdump(entry.chomp, customer_id, hashfile_id, hashtype)
    elsif file_type == 'shadow'
      importShadow(entry.chomp, customer_id, hashfile_id, hashtype)
    elsif file_type == 'raw'
      importRaw(entry.chomp, customer_id, hashfile_id, hashtype)
    elsif file_type == 'dsusers'
      importDsusers(entry.chomp, customer_id, hashfile_id, hashtype)
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
