# Pleroma: A lightweight social networking server
# Copyright © 2017-2021 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.RelMe do
  @options [
    max_body: 2_000_000,
    receive_timeout: 2_000
  ]

  if Pleroma.Config.get(:env) == :test do
    def parse(url) when is_binary(url), do: parse_url(url)
  else
    @cachex Pleroma.Config.get([:cachex, :provider], Cachex)
    def parse(url) when is_binary(url) do
      @cachex.fetch!(:rel_me_cache, url, fn _ ->
        {:commit, parse_url(url)}
      end)
    rescue
      e -> {:error, "Cachex error: #{inspect(e)}"}
    end
  end

  def parse(_), do: {:error, "No URL provided"}

  defp parse_url(url) do
    with {:ok, %Tesla.Env{body: html, status: status}} when status in 200..299 <-
           Pleroma.HTTP.get(url, [], @options),
         {:ok, html_tree} <- Floki.parse_document(html),
         data <-
           Floki.attribute(html_tree, "link[rel~=me]", "href") ++
             Floki.attribute(html_tree, "a[rel~=me]", "href") do
      {:ok, data}
    end
  rescue
    e -> {:error, "Parsing error: #{inspect(e)}"}
  end

  def maybe_put_rel_me("http" <> _ = target_page, profile_urls) when is_list(profile_urls) do
    with {:parse, {:ok, rel_me_hrefs}} <- {:parse, parse(target_page)},
         {:link_match, true} <-
           {:link_match, Enum.any?(rel_me_hrefs, fn x -> x in profile_urls end)} do
      "me"
    else
      e -> {:error, {:could_not_verify, target_page, e}}
    end
  rescue
    e -> {:error, {:could_not_fetch, target_page, e}}
  end

  def maybe_put_rel_me(_, _) do
    {:error, :invalid_url}
  end
end
