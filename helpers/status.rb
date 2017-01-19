helpers do
  def isBusy?
    @results = `ps awwux | grep -i Hashcat | egrep -v "(grep|sudo|resque|^$)"`
    return true if @results.length > 1
  end

  def isDevelopment?
    Sinatra::Base.development?
  end

  def isOldVersion()
    begin
      if Targets.all
        return true
      else
        return false
      end
    rescue
      # we really need a better upgrade process
      return false
    end
  end
end
