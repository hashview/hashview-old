class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user = user
    @record = record
  end

  def admin_access?
    admin?
  end

  def owner?
    record.owner == user.username
  end

  def admin?
    user.admin
  end
end
