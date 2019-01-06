require 'application_policy'

class HashfilesPolicy < ApplicationPolicy
  def list?
    return hashfiles_exist? unless admin_access?
    true
  end

  private

  def hashfile_ids
    Jobs.select_map(:hashfile_id)
  end

  def hashfiles_exist?
    hashfile_ids.include? record.id
  end
end
