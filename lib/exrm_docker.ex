defmodule ExrmDocker do
  @moduledoc """
  Dockerize your Elixir release

  # Create a release and docker image
    mix release --docker
  # Then start a container with the created image
    docker run -itd <image_id> console
  # Attach to the running Elixir shell
    docker attach <image_id>
  """

  defstruct [:from, :maintainer, :entrypoint, :copy_rel, :pre_copy, :post_copy]

  @build_path Path.join(["_build", "exrm_docker"])
  @dockerfile Path.join([@build_path, "Dockerfile"])
  @port_opts [:stderr_to_stdout, :exit_status, :binary, {:line, 255}]

  @doc """
  Build a Docker image and add the application release.
  This will open a port process and display the `docker build` output.
  """
  @spec build(String.t) :: :ok
  def build(tag) do
    port = Port.open({:spawn, "docker build -f #{@dockerfile} -t #{tag} ."}, @port_opts)
    docker_output(port)
  end

  @doc """
  Generate a Dockerfile depending on the project name and exrm_docker
  configurations of the current project.

  Configuration options:
      image      default: "centos",        # Which image to use
      version    default: nil,             # Which image version to use
      maintainer default: nil,             # Image maintainer
      copy_rel   default: "COPY rel /rel", # Copy the release to the container
      pre_copy   default: nil,             # Any Dockerfile commands before copy
      post_copy  default: nil,             # Any Dockerfile commands after copy
      entrypoint default: nil              # Entrypoint of the image
  """
  @spec build_dockerfile(String.t) :: :ok | {:error, :file.posix}
  def build_dockerfile(project) do
    new(project)
    |> to_dockerfile
    |> create_dockerfile
  end

  @spec new(String.t) :: %ExrmDocker{}
  defp new(project) do
    image = Application.get_env(:exrm_docker, :image, "centos")
    version = Application.get_env(:exrm_docker, :version, nil)
    maintainer = Application.get_env(:exrm_docker, :maintainer, nil)
    pre_copy = Application.get_env(:exrm_docker, :pre_copy, nil)
    copy_rel = Application.get_env(:exrm_docker, :copy_rel, "COPY rel /rel")
    post_copy = Application.get_env(:exrm_docker, :post_copy, nil)
    entrypoint = Application.get_env(:exrm_docker, :entrypoint, nil)
    entrypoint_args = Application.get_env(:exrm_docker, :entrypoint_args, nil)
    %ExrmDocker{
      from: build_from(image, version),
      maintainer: build_maintainer(maintainer),
      pre_copy: pre_copy,
      copy_rel: copy_rel,
      post_copy: post_copy,
      entrypoint: build_entrypoint(entrypoint, project, entrypoint_args)
    }
  end

  @spec to_dockerfile(%ExrmDocker{}) :: String.t
  defp to_dockerfile(struct) do
    """
    #{struct.from}
    #{struct.maintainer}
    #{struct.pre_copy}
    #{struct.copy_rel}
    #{struct.post_copy}
    #{struct.entrypoint}
    """
  end

  @spec create_dockerfile(String.t) :: :ok | {:error, :file.posix}
  defp create_dockerfile(dockerfile_contents) do
    :ok = File.mkdir_p(@build_path)
    File.write(@dockerfile, dockerfile_contents)
  end

  @spec docker_output(port, String.t | nil) :: :ok
  defp docker_output(port, last \\ nil) do
    receive do
      {^port, {:data, {_, data}}} ->
        if data |> String.contains?("\r") do
          IO.write(data)
          docker_output(port, data)
        else
          if last, do: IO.puts(last)
          IO.puts(data)
          docker_output(port)
        end
      {^port, {:exit_status, _}} ->
        :ok
    end
  end

  @spec build_from(String.t, String.t | nil) :: String.t
  defp build_from(image, nil), do: "FROM #{image}"
  defp build_from(image, version), do: "FROM #{image}:#{version}"

  @spec build_maintainer(String.t | nil) :: String.t
  defp build_maintainer(nil), do: ""
  defp build_maintainer("MAINTAINER" <> _rest = maintainer), do: maintainer
  defp build_maintainer(maintainer), do: "MAINTAINER #{maintainer}"

  @spec build_entrypoint(String.t | nil, String.t, String.t) :: String.t
  defp build_entrypoint(nil, project, nil) do
    "ENTRYPOINT [\"/rel/#{project}/bin/#{project}\"]"
  end

  defp build_entrypoint(nil, project, args) when is_binary(args) do
    build_entrypoint(nil, project, [args])
  end

  defp build_entrypoint(nil, project, args) when is_list(args) do
    args = args
    |> Enum.map(&("\"#{&1}\""))
    |> Enum.join(", ")
    "ENTRYPOINT [\"/rel/#{project}/bin/#{project}\", #{args}]"
  end

  defp build_entrypoint("ENTRYPOINT" <> _rest = entrypoint, _, _args), do: entrypoint
  defp build_entrypoint(entrypoint, _, _args), do: "ENTRYPOINT #{entrypoint}"
end
