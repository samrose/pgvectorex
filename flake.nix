{
  description = "Elixir escript application with setup command and local Mix/Hex";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        elixir = pkgs.beam.packages.erlang.elixir;
        
        elixirScript = pkgs.writeText "script.exs" ''
          Mix.install([
            {:postgrex, "~> 0.19.1"},
            {:jason, "~> 1.0"},
            {:pgvector, "~> 0.3.0"}
          ])
          defmodule PgvectorExample do
            @moduledoc """
            A simple example of using pgvector in Supabase with Elixir.
            """
            
            @doc """
            Create the books table if it doesn't exist.
            """
            def create_table do
              {:ok, conn} = connect_to_db()

              create_extension_query = "CREATE EXTENSION IF NOT EXISTS vector"
              create_table_query = """
              CREATE TABLE IF NOT EXISTS books (
                id SERIAL PRIMARY KEY,
                title TEXT NOT NULL,
                embedding vector(384) NOT NULL
              )
              """

              Postgrex.query!(conn, create_extension_query, [])
              Postgrex.query!(conn, create_table_query, [])
            end

            @doc """
            Generate sample data for pgvector.
            """
            def generate_sample_data do
              [
                %{title: "The Great Gatsby", embedding: generate_embedding()},
                %{title: "To Kill a Mockingbird", embedding: generate_embedding()},
                %{title: "1984", embedding: generate_embedding()},
                %{title: "Pride and Prejudice", embedding: generate_embedding()},
                %{title: "The Catcher in the Rye", embedding: generate_embedding()}
              ]
            end

            @doc """
            Generate a random embedding vector.
            """
            def generate_embedding do
              1..384 |> Enum.map(fn _ -> :rand.normal() end)
            end

            @doc """
            Insert data into Supabase using Postgrex.
            """
            def insert_data(data) do
              {:ok, conn} = connect_to_db()
              query = "INSERT INTO books (title, embedding) VALUES ($1, $2)"
              Enum.each(data, fn %{title: title, embedding: embedding} ->
                Postgrex.query!(conn, query, [title, embedding])
              end)
            end

            @doc """
            Perform a similarity search using pgvector.
            """
            def similarity_search(query_embedding) do
              {:ok, conn} = connect_to_db()

              query = """
              SELECT title, embedding <-> $1 AS distance
              FROM books
              ORDER BY distance
              LIMIT 5
              """

              result = Postgrex.query!(conn, query, [query_embedding])

              Postgrex.close!(conn,query,[])

              result.rows
            end
            defp connect_to_db do
              Postgrex.Types.define(PgVectorExample.PostgrexTypes, Pgvector.extensions(), [])
              Postgrex.start_link(
                hostname: System.get_env("SUPABASE_URL"),
                username: System.get_env("SUPABASE_USER"),
                password: System.get_env("SUPABASE_PASSWORD"),
                port: String.to_integer(System.get_env("SUPABASE_PORT")),
                database: "postgres",
                ssl: true,
                types: PgVectorExample.PostgrexTypes
              )
            end
          end
          IO.inspect(System.get_env("SUPABASE_URL"), label: "Supabase URL")
          PgvectorExample.create_table()

          data = PgvectorExample.generate_sample_data()
          PgvectorExample.insert_data(data)

          query_embedding = PgvectorExample.generate_embedding()
          similar_books = PgvectorExample.similarity_search(query_embedding)

          IO.inspect(similar_books, label: "Similar books")
        '';
        
        setupScript = pkgs.writeShellScriptBin "elixir-setup" ''
          echo "Setting up Elixir environment..."

          # Set up local Mix and Hex
          mkdir -p .nix-mix .nix-hex
          export MIX_HOME=$PWD/.nix-mix
          export HEX_HOME=$PWD/.nix-hex
          export PATH=$MIX_HOME/bin:$HEX_HOME/bin:$PATH

          ${elixir}/bin/mix local.hex --force
          ${elixir}/bin/mix local.rebar --force
          echo "Elixir setup complete. You can now run your application."
        '';

        runScript = pkgs.stdenv.mkDerivation {
          name = "run-elixir-script";
          
          buildInputs = [ pkgs.makeWrapper elixir pkgs.cacert ];
          
          unpackPhase = "true";  # We don't need to unpack anything
          
          installPhase = ''
            mkdir -p $out/bin
            cat > $out/bin/run-elixir-script <<EOF
            #!/bin/sh
            export PATH=\$MIX_HOME/bin:\$HEX_HOME/bin:\$PATH
            export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt

            ${elixir}/bin/elixir ${elixirScript} "\$@"
            EOF
            chmod +x $out/bin/run-elixir-script
            wrapProgram $out/bin/run-elixir-script \
              --set SSL_CERT_FILE ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
          '';
          
          meta = with pkgs.lib; {
            description = "Run Elixir script with proper environment setup";
            platforms = platforms.all;
          };
        };

      in
      {
        packages = {
          pgVec = runScript;
          setup = setupScript;
        };

        apps = {
          pgVec = flake-utils.lib.mkApp {
            drv = runScript;
          };
          setup = {
            type = "app";
            program = "${setupScript}/bin/elixir-setup";
          };
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            elixir
          ];
          shellHook = ''
            if [ -f .env ]; then
                source .env
            fi
            mkdir -p .nix-mix .nix-hex
            export MIX_HOME=$PWD/.nix-mix
            export HEX_HOME=$PWD/.nix-hex
            export PATH=$MIX_HOME/bin:$HEX_HOME/bin:$PATH
          '';
        };
      }
    );
}