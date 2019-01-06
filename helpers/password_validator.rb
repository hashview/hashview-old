class PasswordValidator
  attr_reader :password, :required_complexity
  REQUIRED_COMPLEXITY = 3

  def self.call(password)
    new(password).call
  end

  def initialize(password)
    @password = password
  end

  def call
    valid_length? && valid_complexity?
  end

  def valid_length?
    password.size >= 8
  end

  def valid_complexity?
    score = uppercase + digit + special + lowercase
    score >= REQUIRED_COMPLEXITY
  end

  private

  def uppercase
    password.match?(/[A-Z]/) ? 1 : 0
  end

  def digit
    password.match?(/\d/) ? 1 : 0
  end

  def special
    password.match?(/\W/) ? 1 : 0
  end

  def lowercase
    password.match?(/[a-z]{1}/) ? 1 : 0
  end
end
