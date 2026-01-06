defmodule MaculaMarketplace.Licensing.UCAN do
  @moduledoc """
  UCAN (User Controlled Authorization Network) token management.

  UCAN tokens are capability-based authorization tokens that enable
  decentralized licensing. Publishers issue tokens to consumers,
  granting them specific capabilities (deploy, use, redistribute).

  ## Token Structure

  UCAN tokens follow the UCAN 0.10.0 specification:
  - `iss`: Issuer DID (publisher org)
  - `aud`: Audience DID (consumer org)
  - `cap`: Capabilities granted
  - `exp`: Expiration timestamp
  - `prf`: Proof chain (for delegation)
  - `fct`: Facts (metadata like tier, seats)
  - `sig`: Ed25519 signature

  ## Usage

      # Create a license token
      {:ok, token} = UCAN.create_token(
        issuer_did: "did:macula:io.macula.publisher",
        audience_did: "did:macula:io.macula.consumer",
        capabilities: [%{with: "io.macula.publisher.my-app", can: "deploy"}],
        expires_at: ~U[2025-12-31 23:59:59Z],
        facts: %{tier: "pro", seats: 5}
      )

      # Verify a token
      {:ok, :valid} = UCAN.verify_token(token, trust_roots)

      # Decode without verification
      {:ok, claims} = UCAN.decode_token(token)
  """

  require Logger

  @ucan_version "0.10.0"

  @doc """
  Create a new UCAN license token.

  ## Options

  - `:issuer_did` - Publisher's DID (required)
  - `:audience_did` - Consumer's DID (required)
  - `:capabilities` - List of capability maps (required)
  - `:private_key` - Issuer's Ed25519 private key (required)
  - `:expires_at` - Expiration DateTime (optional, nil = perpetual)
  - `:not_before` - Not valid before DateTime (optional)
  - `:facts` - Metadata map (optional)
  - `:proofs` - List of parent UCAN CIDs for delegation (optional)
  """
  def create_token(opts) do
    issuer_did = Keyword.fetch!(opts, :issuer_did)
    audience_did = Keyword.fetch!(opts, :audience_did)
    capabilities = Keyword.fetch!(opts, :capabilities)
    private_key = Keyword.fetch!(opts, :private_key)

    expires_at = Keyword.get(opts, :expires_at)
    not_before = Keyword.get(opts, :not_before)
    facts = Keyword.get(opts, :facts, %{})
    proofs = Keyword.get(opts, :proofs, [])

    payload = %{
      ucv: @ucan_version,
      iss: issuer_did,
      aud: audience_did,
      cap: capabilities,
      exp: expires_at && DateTime.to_unix(expires_at),
      nbf: not_before && DateTime.to_unix(not_before),
      fct: facts,
      prf: proofs
    }

    # Call macula_nifs to create and sign the token
    case :macula_ucan_nif.nif_ucan_create(
           issuer_did,
           audience_did,
           Jason.encode!(capabilities),
           private_key,
           %{
             exp: payload.exp,
             nbf: payload.nbf,
             fct: Jason.encode!(facts),
             prf: proofs
           }
         ) do
      {:ok, token} ->
        {:ok, token}

      {:error, reason} ->
        Logger.error("[UCAN] Failed to create token: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Verify a UCAN token against trust roots.

  Trust roots are the DIDs of organizations we trust to issue licenses.
  The token's issuer must be in the trust roots or have a valid
  delegation chain leading to a trust root.
  """
  def verify_token(token, trust_roots) when is_list(trust_roots) do
    trust_roots_json = Jason.encode!(trust_roots)

    case :macula_ucan_nif.nif_ucan_verify(token, trust_roots_json) do
      {:ok, :valid} ->
        {:ok, :valid}

      {:ok, :invalid, reason} ->
        {:error, reason}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Decode a UCAN token without verification.

  Use this to inspect token claims. Always verify before
  making authorization decisions.
  """
  def decode_token(token) do
    case :macula_ucan_nif.nif_ucan_decode(token) do
      {:ok, claims_json} ->
        {:ok, Jason.decode!(claims_json)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if a token grants a specific capability.
  """
  def has_capability?(token, resource, action) do
    with {:ok, claims} <- decode_token(token),
         capabilities <- Map.get(claims, "cap", []) do
      Enum.any?(capabilities, fn cap ->
        cap_resource = Map.get(cap, "with")
        cap_action = Map.get(cap, "can")

        matches_resource?(cap_resource, resource) and matches_action?(cap_action, action)
      end)
    else
      _ -> false
    end
  end

  @doc """
  Check if a token is expired.
  """
  def expired?(token) do
    case decode_token(token) do
      {:ok, %{"exp" => nil}} ->
        false

      {:ok, %{"exp" => exp}} ->
        DateTime.utc_now() |> DateTime.to_unix() > exp

      _ ->
        true
    end
  end

  @doc """
  Get the token's CID (content identifier) for revocation lists.
  """
  def token_cid(token) do
    case :macula_ucan_nif.nif_ucan_cid(token) do
      {:ok, cid} -> {:ok, cid}
      {:error, reason} -> {:error, reason}
    end
  end

  # Private helpers

  defp matches_resource?(pattern, resource) when pattern == resource, do: true
  defp matches_resource?(pattern, resource) when is_binary(pattern) do
    # Support wildcards like "io.macula.acme.*"
    if String.ends_with?(pattern, "*") do
      prefix = String.slice(pattern, 0..-2//1)
      String.starts_with?(resource, prefix)
    else
      pattern == resource
    end
  end
  defp matches_resource?(_, _), do: false

  defp matches_action?(pattern, action) when pattern == action, do: true
  defp matches_action?("*", _action), do: true
  defp matches_action?(_, _), do: false
end
