require 'rubygems'
require 'sinatra'
require './model/master'

def detected_hash_format(hash)
  # Detect if pwdump file format
  if hash =~ /^[^:]+:\d+:.*:.*:.*:.*:$/
    return 'pwdump'
  # Detect if shadow
  elsif hash =~ /^.*:.*:\d*:\d*:\d*:\d*:\d*:\d*:$/
    return 'shadow'
  elsif hash =~ /^\w{32}$/
    return 'ntlm_only'
  else
    return 'File Format or Hash not supported'
  end
end

def import_pwdump(hash, customer_id, job_id, type)

  data = hash.split(':')
  if machine_acct?(data[0])
    return
  end

  # if hashtype is lm
  if type == '3000'
    # import LM
    lm_hashes = data[2].scan(/.{16}/)

    target_lm1 = Targets.new
    target_lm1.username = data[0]
    target_lm1.originalhash = lm_hashes[0].downcase
    target_lm1.hashtype = '3000'
    target_lm1.jobid = job_id
    target_lm1.customerid = customer_id
    target_lm1.cracked = false
    target_lm1.save

    target_lm2 = Targets.new
    target_lm2.username = data[0]
    target_lm2.originalhash = lm_hashes[1].downcase
    target_lm2.hashtype = '3000'
    target_lm2.jobid = job_id
    target_lm2.customerid = customer_id
    target_lm2.cracked = false
    target_lm2.save
  end

  # if hashtype is ntlm
  if type == '1000'
    # import NTLM
    target_ntlm = Targets.new
    target_ntlm.username = data[0]
    target_ntlm.originalhash = data[3].downcase
    target_ntlm.hashtype = '1000'
    target_ntlm.jobid = job_id
    target_ntlm.customerid = customer_id
    target_ntlm.cracked = false
    target_ntlm.save
  end
  #return 0
end

def machine_acct?(username)
  if username =~ /\$/
    return true
  else
    return false
  end
end


def import_shadow(hash, customer_id, job_id, type)

  data = hash.split(':')
  target = Targets.new
  target.username = data[0]
  target.originalhash = data[1]
  target.hashtype = type
  target.jobid = job_id
  target.customerid = customer_id
  target.cracked = false
  target.save
end

def import_raw(hash, customer_id, job_id, type)

  target_raw = Targets.new
  target_raw.username = 'NULL'
  target_raw.originalhash = hash.downcase
  target_raw.hashtype = type
  target_raw.jobid = job_id
  target_raw.customerid = customer_id
  target_raw.cracked = false
  target_raw.save
end

def get_mode(hash)
  @modes = []
  if hash =~ /^\w{32}$/
    @modes.push('0')	# MD5
    @modes.push('1000')	# NTLM
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
  elsif hash =~ /^[^\\\/:*?"<>|]{1,20}[:]{2,3}[^\\\/:*?"<>|]{1,20}?:[a-f0-9]{48}:[a-f0-9]{48}:[a-f0-9]{16}$/
    @modes.push('5500')	# NetNTLMv1-VANILLA / NetNTLMv1+ESS
  elsif hash =~ /^[^\\\/:*?"<>|]{1,20}\\?[^\\\/:*?"<>|]{1,20}[:]{2,3}[^\\\/:*?"<>|]{1,20}:?[^\\\/:*?"<>|]{1,20}:[a-f0-9]{32}:[a-f0-9]+$/
    @modes.push('5600')	# NetNTLMv2
  else
    @modes.push('99999')	# Plain text
  end
  return @modes
end

def mode_to_friendly(mode)
  if mode == '0'
    return 'MD5'
  elsif mode == '1000'
    return 'NTLM'
  elsif mode == '3000'
    return 'LM'
  elsif mode == '500'
    return 'md5crypt'
  elsif mode == '3200'
    return 'bcrypt'
  elsif mode == '7400'
    return 'sha256crypt'
  elsif mode == '1800'
    return 'sha512crypt'
  elsif mode == '1500'
    return 'descrypt'
  elsif mode == '5500'
    return 'NetNTLMv1'
  elsif mode == '5600'
    return 'NetNTLMv2'
  else
    return 'unknown'
  end
end

def friendly_to_mode(friendly)
  if friendly == 'MD5'
    return '0'
  elsif friendly == 'NTLM'
    return '1000'
  elsif friendly == 'LM'
    return '3000'
  elsif friendly == 'md5crypt'
    return '500'
  elsif friendly == 'bcrypt'
    return '3200'
  elsif friendly == 'sha512crypt'
    return '7400'
  elsif friendly == 'sha256crypt'
    return '1800'
  elsif friendly == 'descrypt'
    return '1500'
  elsif friendly == 'NetNTLMv1'
    return '5500'
  elsif friendly == 'NetNTLMv2'
    return '5600'
  else
    return '99999'
  end
end

def import_hash(hashFile, customer_id, job_id, filetype, hashtype)
  hashFile.each do |entry|
    if filetype == 'pwdump'
      import_pwdump(entry.chomp, customer_id, job_id, hashtype)
    elsif filetype == 'shadow'
      import_shadow(entry.chomp, customer_id, job_id, hashtype)
    elsif filetype == 'raw'
      import_raw(entry.chomp, customer_id, job_id, hashtype)
    else
      return 'Unsupported hash format detected'
    end
  end
end

def detect_hashfile_type(hashFile)

  @filetypes = []
  File.readlines(hashFile).each do | entry |
    if detected_hash_format(entry.chomp) == 'pwdump'
      @filetypes.push('pwdump') unless @filetypes.include?('pwdump')
    elsif detected_hash_format(entry.chomp) == 'shadow'
      @filetypes.push('shadow') unless @filetypes.include?('shadow')
    else
      @filetypes.push('raw') unless @filetypes.include?('raw')
    end
  end
  return @filetypes
end

def detect_hash_type(hashFile, fileType)

  @hashtypes = []
  File.readlines(hashFile).each do | entry |
    if fileType == 'pwdump'
      elements = entry.split(':')
      @modes = get_mode(elements[2])
      @modes.each do | mode |
        @hashtypes.push(mode) unless @hashtypes.include?(mode) # LM
      end
      @modes = get_mode(elements[3])
      @modes.each do | mode |
        @hashtypes.push(mode) unless @hashtypes.include?(mode) # NTLM
      end
    elsif fileType == 'shadow'
      elements = entry.split(':')
      @modes = get_mode(elements[1])
      @modes.each do | mode |
        @hashtypes.push(mode) unless @hashtypes.include?(mode)
      end
    else
      @modes = get_mode(entry)
      @modes.each do | mode |
        @hashtypes.push(mode) unless @hashtypes.include?(mode)
      end
    end
  end
  return @hashtypes
end
