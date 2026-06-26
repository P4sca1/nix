{
  inputs,
  ...
}:
{
  flake.nixosModules.hermes-agent =
    { config, ... }:
    {
      imports = [ inputs.hermes-agent.nixosModules.default ];

      sops.secrets."hermes-env" = {
        format = "yaml";
      };

      # https://hermes-agent.nousresearch.com/docs/getting-started/nix-setup/
      services.hermes-agent = {
        enable = true;
        environmentFiles = [ config.sops.secrets."hermes-env".path ];
        container = {
          enable = true;
          image = "ubuntu:24.04";
          backend = "docker";
          hostUsers = [ "pascal" ];
          extraVolumes = [ "/home/pascal/agents/hermes:/projects:rw" ];
        };
        addToSystemPackages = true; # Add hermes CLI to PATH and set HERMES_HOME system wide to share state
        settings = {
          custom_providers = [
            {
              name = "procyde";
              base_url = "https://pia.procyde.online/v1";
              key_env = "PIA_API_KEY";
              api_mode = "chat_completions";
              models = {
                "PIA-1" = {
                  supports_vision = false;
                };
              };
            }
          ];
          model = {
            provider = "procyde";
            default = "PIA-1";
            toolsets = [ "all" ];
            max_turns = 100;
            terminal = {
              backend = "local";
              cwd = ".";
              timeout = 180;
            };
            compression = {
              enabled = true;
              threshold = 0.85;
              summary_model = "PIA-1";
            };
            memory = {
              memory_enabled = true;
              user_profile_enabled = true;
            };
            agent = {
              max_turns = 60;
              verbose = false;
            };
          };
        };
      };
    };
}
