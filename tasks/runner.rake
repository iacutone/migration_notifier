task :runner do
	notifier = INotify::Notifier.new
  notifier.run
end