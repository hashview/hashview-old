class JobsPolicy < ApplicationPolicy
  class Scope
    attr_reader :user, :scope

    def initialize(user, scope)
      @user  = user
      @scope = scope
    end

    def resolve
      if user.admin
        scope.all
      else
        scope.where(owner: user.username)
      end
    end
  end

  def edit?
    owner? || admin?
  end
end
