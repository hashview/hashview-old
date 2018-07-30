helpers do
  def check_password_complexity(password, complexity)
    @password = password
    @require_complexity = complexity
    length_is_valid? && complexity_is_valid?
  end

  def length_is_valid?
    @password.size < 8
  end

  def complexity_is_valid?
    score = uppercase_letters? + digits? + extra_chars? + downcase_letters?
    score < @require_complexity
  end

  def uppercase_letters?
    @password =~ /[A-Z]/ ? 1 : 0
  end

  def digits?
    @password =~ /\d/ ? 1 : 0
  end

  def extra_chars?
    @password =~ /\W/ ? 1 : 0
  end

  def downcase_letters?
    @password =~ /[a-z]{1}/ ? 1 : 0
  end
end
