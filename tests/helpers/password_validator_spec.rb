require File.expand_path(File.join('..', 'test_helper.rb'), __dir__)

class PasswordValidatorTest < MiniTest::Unit::TestCase
  def test_password_validator_valid_length
    assert_equal PasswordValidator.call('1234567'), false
  end

  def test_password_validator_lowercase
    assert_equal PasswordValidator.call('omgplains'), false
  end

  def test_password_validator_lowercase_digit
    assert_equal PasswordValidator.call('omgplain5'), false
  end

  def test_password_validator_lowercase_special
    assert_equal PasswordValidator.call('omgpl@ins'), false
  end

  def test_password_validator_lowercase_digit_special
    assert_equal PasswordValidator.call('0mgpl@ins'), true
  end

  def test_password_validator_lowercase_digit_special_uppercase
    assert_equal PasswordValidator.call('Omgpl@aIn5'), true
  end
end
