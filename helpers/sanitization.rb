helpers do
  # Take you to the var wash baby
  def varWash(params)
    params.keys.each do |key|
      if params[key].is_a?(String)
        params[key] = cleanString(params[key])
      end
      if params[key].is_a?(Array)
        params[key] = cleanArray(params[key])
      end
    end
  end

  def cleanString(text)
    return text.gsub(/[<>'"()\/\\]*/i, '') unless text.nil?
  end

  def cleanArray(array)
    clean_array = []
    array.each do |entry|
      clean_array.push(cleanString(entry))
    end
    return clean_array
  end

end
