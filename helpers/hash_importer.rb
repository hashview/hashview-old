require 'rubygems'
require 'sinatra'
require './model/master'

def detected_hash(hash)
  # Detect if pwdump file format
  if hash =~ /^.*:\d+:.*:.*:.*:.*:$/
    return 'pwdump'
  # Detect if shadow_md5
  elsif hash =~ /^\w+:.*:\d*:\d*:\d*:\d*:\d*:\d*:$/
    return 'shadow'
  elsif hash =~ /^\w{32}$/
    return 'ntlm_only'
  else
    return 'File Format or Hash not supported'
  end
end

def import_pwdump(hash, job_id, description, type)

  data = hash.split(':')
  if machine_acct?(data[0])
    return
  end

  # if hashtype is lm
  if type == 3000
    # import LM
    lm_hashes = data[2].scan(/.{16}/)

    target_lm1 = Targets.new
    target_lm1.username = data[0]
    target_lm1.originalhash = lm_hashes[0].downcase
    target_lm1.hashtype = get_mode(lm_hashes[0])
    target_lm1.jobid = job_id
    target_lm1.description = description
    target_lm1.cracked = false
    target_lm1.save

    target_lm2 = Targets.new
    target_lm2.username = data[0]
    target_lm2.originalhash = lm_hashes[1].downcase
    target_lm2.hashtype = get_mode(lm_hashes[1])
    target_lm2.jobid = job_id
    target_lm2.description = description
    target_lm2.cracked = false
    target_lm2.save
  end
  
  # if hashtype is ntlm
  if type == 1000
    # import NTLM
    target_ntlm = Targets.new
    target_ntlm.username = data[0]
    target_ntlm.originalhash = data[3].downcase
    target_ntlm.hashtype = get_mode(data[3])
    target_ntlm.jobid = job_id
    target_ntlm.description = description
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


def import_shadow(hash, job_id, description)

  data = hash.split(':')
  target = Targets.new
  target.username = data[0]
  target.originalhash = data[1]
  target.hashtype = get_mode(data[1])
  target.jobid = jobid
  target.cracked = false
  target.save
end


def import_ntlm_only(hash, job_id, description)

  target_ntlm = Targets.new
  target_ntlm.username = 'NULL'
  target_ntlm.originalhash = hash.downcase
  target_ntlm.hashtype = get_mode(hash)
  target_ntlm.jobid = job_id
  target_ntlm.description = description
  target_ntlm.cracked = false
  target_ntlm.save
end

def get_mode(hash)
  # matches ntlm
  if hash =~ /^\w{32}$/
    return '1000'	# NTLM
  elsif hash =~ /^\w{16}$/
    return '3000'	# LM
  elsif hash =~ %r{^\$1\$[\.\/0-9A-Za-z]{0,8}\$[\.\/0-9A-Za-z]{22}$}
    return '500' 	# md5crypt
  elsif hash =~ /^\$2a\$\d?\$.{53}$/
    return '3200'	# bcrypt, Blowfish(OpenBSD)
  elsif hash =~ %r{^\$5\$rounds=\d+\$[\.\/0-9A-Za-z]{0,8}\$[\.\/0-9A-Za-z]{22}$}
    return '7400'	# sha256crypt, SHA256(Unix)
  elsif hash =~ %r{^\$6\$[\.\/0-9A-Za-z]{4,9}\$[\.\/0-9A-Za-z]{86}$}
    return '1800'	# sha512crypt, SHA512(Unix)
  elsif hash =~ %r{^[\.\/0-9A-Za-z]{13}$}
    return '1500'	# descrypt, DES(Unix), Traditional DES
  else
    return '99999'	# Plain text
  end
end

def import_hash(hashFile, job_id, description, hashtype)
  hashFile.each do |entry|

    if detected_hash(entry.chomp) == 'pwdump'
      import_pwdump(entry, job_id, description, hashtype)
    elsif detected_hash(entry.chomp) == 'shadow'
      import_shadow(entry, job_id, description)
    elsif detected_hash(entry) == 'ntlm_only'
      import_ntlm_only(entry, job_id, description)
    else
      return 'Unsupported hash format detected'
    end
  end
end
