helpers do
  def isBusy?
    @results = `ps awwux | grep -i Hashcat | egrep -v "(grep|sudo|resque|^$)"`
    return true if @results.length > 1
  end
end
