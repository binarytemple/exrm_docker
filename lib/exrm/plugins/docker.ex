defmodule ReleaseManager.Plugin.ExrmDocker do
  use ReleaseManager.Plugin

  def before_release(%{docker: true} = config) do
    ExrmDocker.build_dockerfile(config.name)
  end
  def before_release(_config), do: nil

  def after_release(_config), do: nil

  def after_package(%{docker: true} = _config) do
    ExrmDocker.build
  end
  def after_package(_config), do: nil

  def after_cleanup(_config), do: nil
end
