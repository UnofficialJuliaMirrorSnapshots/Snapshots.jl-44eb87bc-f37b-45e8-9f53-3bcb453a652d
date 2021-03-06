##### Beginning of file

module GitLabSrcHost # Begin submodule Snapshots.Hosts.GitLabSrcHost

__precompile__(true)

import ..Types
import ..Utils

import Dates
import HTTP
import JSON
import TimeZones

import ..delayederror

function new_gitlab_session(
        ;
        gitlab_group::String,
        gitlab_bot_username::String,
        gitlab_bot_personal_access_token::String,
        )::Function

    _gitlab_group::String = strip(
        convert(String, gitlab_group)
        )
    _provided_gitlab_bot_username::String = strip(
        convert(String, gitlab_bot_username,)
        )
    _gitlab_bot_personal_access_token::String = strip(
        convert(String, gitlab_bot_personal_access_token)
        )

    function _get_gitlab_username()::String
        method::String = "GET"
        url::String = "https://gitlab.com/api/v4/user"
        headers::Dict{String, String} = Dict(
            "PRIVATE-TOKEN" => gitlab_bot_personal_access_token,
            )
        http_request = () -> HTTP.request(
            method,
            url,
            headers,
            )
        r::HTTP.Messages.Response = Utils.retry_function_until_success(
            http_request;
            max_attempts = 10,
            seconds_to_wait_between_attempts = 180,
        )
        r_body::String = String(r.body)
        parsed_r_body::Dict = JSON.parse(r_body)
        username::String = parsed_r_body["name"]
        username_stripped::String = strip(username)
        return username_stripped
    end

    function _get_all_my_namespaces()::Vector{Dict}
        method::String = "GET"
        url::String = "https://gitlab.com/api/v4/namespaces"
        headers::Dict{String, String} = Dict(
            "PRIVATE-TOKEN" => gitlab_bot_personal_access_token,
            )
        http_request = () -> HTTP.request(
            method,
            url,
            headers,
            )
        r = Utils.retry_function_until_success(
            http_request;
            max_attempts = 10,
            seconds_to_wait_between_attempts = 180,
        )
        r_body = String(r.body)
        parsed_body = JSON.parse(r_body)
        return parsed_body
    end

    function _get_namespace_id_for_my_group()::Int
        all_my_namespaces::Vector{Dict} = _get_all_my_namespaces()
        result::Int = 0
        for i = 1:length(all_my_namespaces)
            namespace = all_my_namespaces[i]
            if strip(namespace["name"]) == strip(_gitlab_group)
                result = namespace["id"]
            end
        end
        if result == 0
            delayederror("Could not find the id for my group")
        end
        return result
    end

    @info("Attempting to authenticate to GitLab...")
    _gitlab_username::String = _get_gitlab_username()
    if lowercase(strip(_gitlab_username)) !=
            lowercase(strip(_provided_gitlab_bot_username))
        delayederror(
            string(
                "Provided GitLab username ",
                "(\"$(_provided_gitlab_bot_username)\") ",
                "does not match ",
                "actual GitLab username ",
                "(\"$(_gitlab_username)\").",
                )
            )
    else
        @info(
            string(
                "Provided GitLab username matches ",
                "actual GitLab username.",
                ),
            _provided_gitlab_bot_username,
            _gitlab_username,
            )
    end
    @info("Successfully authenticated to GitLab :)")

    @info(
        string(
            "GitLab username: ",
            "$(_get_gitlab_username())",
            )
        )
    @info(
        string(
            "GitLab group (a.k.a. organization): ",
            "$(_gitlab_group)",
            )
        )

    function _create_gist(params::AbstractDict)::Nothing
        gist_description::String = strip(params[:gist_description])
        gist_content::String = strip(params[:gist_content])
        @info("Attempting to create snippet on GitLab...")
        method::String = "POST"
        url::String = "https://gitlab.com/api/v4/snippets"
        headers::Dict{String, String} = Dict(
            "PRIVATE-TOKEN" => gitlab_bot_personal_access_token,
            "content-type" => "application/json",
            )
        params::Dict{String, String} = Dict(
            "title" => "list.txt",
            "file_name" => "list.txt",
            "content" => gist_content,
            "description" => gist_description,
            "visibility" => "public",
            )
        body::String = JSON.json(params)
        try
            r::HTTP.Messages.Response = HTTP.request(
                method,
                url,
                headers,
                body,
                )
            @info("Successfully created snippet on GitLab.")
        catch exception
            @warn("ignoring exception: ", exception,)
        end
    end

    function _get_all_gists()::Vector{Dict}
        @info("Loading the list of all of my GitLab snippets")
        gist_dict_list::Vector{Dict} = Dict[]
        gist_id_list::Vector{Int} = Int[]
        need_to_continue::Bool = true
        current_page_number::Int = 1
        method::String = "GET"
        headers::Dict{String, String} = Dict(
            "PRIVATE-TOKEN" => gitlab_bot_personal_access_token,
            )
        url::String = ""
        while need_to_continue
            url = string(
                "https://gitlab.com/api/v4/snippets",
                "?per_page=100&page=$(current_page_number)&",
                )
            r = HTTP.request(
                method,
                url,
                headers,
                )
            r_body = String(r.body)
            parsed_body = JSON.parse(r_body)
            if length(parsed_body) == 0
                need_to_continue = false
            else
                need_to_continue = true
                current_page_number += 1
                for i = 1:length(parsed_body)
                    gist_dict = parsed_body[i]
                    gist_id = gist_dict["id"]
                    if gist_id in gist_id_list
                        @debug(
                            string("already have this gist"),
                            gist_id,
                        )
                    else
                        push!(gist_id_list, gist_id)
                        push!(gist_dict_list, gist_dict)
                    end
                end
            end
        end
        return gist_dict_list
    end

    function _retrieve_gist(params::AbstractDict)::String
        gist_description_to_match::String = strip(params[:gist_description])
        correct_gist_id::Int = 0
        correct_gist_raw_url::String = ""
        all_my_gists = _get_all_gists()
        for gist in all_my_gists
            if strip(gist["description"]) == gist_description_to_match
                correct_gist_id = gist["id"]
                correct_gist_raw_url = strip(gist["raw_url"])
            end
        end
        result::String = ""
        if correct_gist_id > 0
            @info("Downloading the correct GitLab snippet")
            method::String = "GET"
            headers::Dict{String, String} = Dict(
                "PRIVATE-TOKEN" => gitlab_bot_personal_access_token,
                )
            url::String = strip(correct_gist_raw_url)
            r = HTTP.request(
                method,
                url,
                headers,
                )
            result = strip(String(r.body))
        else
            result = ""
        end
        if length(result) == 0
            delayederror("Could not find the matching GitLab snippet")
        end
        return result
    end

    function _delete_gists(params::AbstractDict)::Nothing
        gist_description_to_match::String = strip(params[:gist_description])
        list_of_gist_ids_to_delete::Vector{Int} = Int[]
        all_my_gists::Vector{Dict} = _get_all_gists()
        for gist in all_my_gists
            if strip(gist["description"]) == gist_description_to_match
                push!(list_of_gist_ids_to_delete, gist["id"],)
            end
        end
        for gist_id_to_delete in list_of_gist_ids_to_delete
            method = "DELETE"
            url = string(
                "https://gitlab.com/api/v4/snippets/$(gist_id_to_delete)",
                )
            headers = Dict(
                "PRIVATE-TOKEN" => gitlab_bot_personal_access_token,
                )
            r = HTTP.request(
                method,
                url,
                headers,
                )
            @info(string("Deleted GitLab snippet id $(gist_id_to_delete)"))
        end
        return nothing
    end

    function _delete_gists_older_than_minutes(params::AbstractDict)::Nothing
        time::TimeZones.ZonedDateTime =
            params[:time]
        delete_gists_older_than_minutes::Int =
            params[:delete_gists_older_than_minutes]
        max_gist_age_milliseconds::Int =
            delete_gists_older_than_minutes*60*1000
        list_of_gist_ids_to_delete::Vector{Int} = Int[]
        all_my_gists::Vector{Dict} = _get_all_gists()
        for gist in all_my_gists
            gist_updated_at = Dates.DateTime(
                gist["updated_at"][1:end-1]
                )
            gist_updated_at_zoned = TimeZones.ZonedDateTime(
                gist_updated_at,
                TimeZones.TimeZone("UTC"),
                )
            gist_age = time - gist_updated_at_zoned
            if gist_age.value > max_gist_age_milliseconds
                push!(list_of_gist_ids_to_delete, gist["id"],)
            end
        end
        for gist_id_to_delete in list_of_gist_ids_to_delete
            method = "DELETE"
            url = string(
                "https://gitlab.com/api/v4/snippets/$(gist_id_to_delete)",
                )
            headers = Dict(
                "PRIVATE-TOKEN" => gitlab_bot_personal_access_token,
                )
            r = HTTP.request(
                method,
                url,
                headers,
                )
            @info(string("Deleted GitLab snippet id $(gist_id_to_delete)"))
        end
        return nothing
    end

    function _repo_name_with_org(
            ;
            repo::AbstractString,
            org::AbstractString,
            )::String
        repo_name_without_org::String = _repo_name_without_org(
            ;
            repo = repo,
            org = org,
            )
        org_stripped::String = strip(
            strip(strip(strip(strip(convert(String, org)), '/')), '/')
            )
        result::String = string(
            org_stripped,
            "/",
            repo_name_without_org,
            )
        return result
    end

    function _repo_name_without_org(
            ;
            repo::AbstractString,
            org::AbstractString,
            )::String
        repo_stripped::String = strip(
            strip(strip(strip(strip(convert(String, repo)), '/')), '/')
            )
        org_stripped::String = strip(
            strip(strip(strip(strip(convert(String, org)), '/')), '/')
            )
        if length(org_stripped) == 0
            result = repo_stripped
        else
            repo_stripped_lowercase::String = lowercase(repo_stripped)
            org_stripped_lowercase::String = lowercase(org_stripped)
            org_stripped_lowercase_withtrailingslash::String = string(
                org_stripped_lowercase,
                "/",
                )
            if startswith(repo_stripped_lowercase,
                    org_stripped_lowercase_withtrailingslash)
                index_start =
                    length(org_stripped_lowercase_withtrailingslash) + 1
                result = repo_stripped[index_start:end]
            else
                result = repo_stripped
            end
        end
        return result
    end

    function _get_destination_url(
            ;
            repo_name::String,
            credentials::Symbol,
            )::String
        repo_name_without_org::String = _repo_name_without_org(
            ;
            repo = repo_name,
            org = _gitlab_group,
            )
        result::String = ""
        if credentials == :with_auth
            result = string(
                "https://",
                _gitlab_username,
                ":",
                _gitlab_bot_personal_access_token,
                "@",
                "gitlab.com/",
                _gitlab_group,
                "/",
                repo_name_without_org,
                )
        elseif credentials == :with_redacted_auth
            result = string(
                "https://",
                _gitlab_username,
                ":",
                "*****",
                "@",
                "gitlab.com/",
                _gitlab_group,
                "/",
                repo_name_without_org,
                )
        elseif credentials == :without_auth
            result =string(
                "https://",
                "gitlab.com/",
                _gitlab_group,
                "/",
                repo_name_without_org,
                )
        else
            delayederror("$(credentials) is not a supported value for credentials")
        end
        return result
    end

    function _gitlab_repo_exists(
            ;
            repo_name::String,
            )::Bool
        repo_name_without_org = _repo_name_without_org(
            ;
            repo = repo_name,
            org = _gitlab_group,
            )
        result::Bool = try
            method = "GET"
            url = string(
                "https://gitlab.com/api/v4/",
                "projects/$(_gitlab_group)%2F$(repo_name)",
                )
            headers = Dict(
                "PRIVATE-TOKEN" => gitlab_bot_personal_access_token,
                )
            r = HTTP.request(
                method,
                url,
                headers,
                )
            true
        catch
            false
        end
        return result
    end

    function _create_repo(params::AbstractDict)::Nothing
        repo_name::String = strip(params[:repo_name])
        repo_name_with_org::String = _repo_name_with_org(
            ;
            repo = repo_name,
            org = _gitlab_group,
            )
        repo_name_without_org::String = _repo_name_without_org(
            ;
            repo = repo_name,
            org = _gitlab_group,
            )
        repo_destination_url_without_auth = _get_destination_url(
            ;
            repo_name = repo_name_without_org,
            credentials = :without_auth,
            )
        # if Utils._url_exists(repo_destination_url_without_auth)
        if false
            @info("According to HTTP GET request, the repo exists.")
        else
            if _gitlab_repo_exists(; repo_name = repo_name_without_org)
                @info("According to the GitLab API, the repo exists.")
            else
                @info(
                    string("Creating new repo on GitLab"),
                    repo_destination_url_without_auth,
                    )
                method = "POST"
                url = "https://gitlab.com/api/v4/projects"
                headers = Dict(
                    "PRIVATE-TOKEN" => gitlab_bot_personal_access_token,
                    "content-type" => "application/json",
                    )
                params = Dict(
                    "name" => repo_name_without_org,
                    "path" => repo_name_without_org,
                    "namespace_id" => _get_namespace_id_for_my_group(),
                    "issues_enabled" => false,
                    "merge_requests_enabled" => false,
                    "jobs_enabled" => false,
                    "wiki_enabled" => false,
                    "snippets_enabled" => false,
                    "resolve_outdated_diff_discussions" => false,
                    "container_registry_enabled" => false,
                    "shared_runners_enabled" => false,
                    "visibility" => "public",
                    "public_jobs" => false,
                    "only_allow_merge_if_pipeline_succeeds" =>
                        false,
                    "only_allow_merge_if_all_discussions_are_resolved" =>
                        false,
                    "lfs_enabled" => false,
                    "request_access_enabled" => false,
                    "printing_merge_request_link_enabled" => false,
                    "initialize_with_readme" => false,
                    )
                body = JSON.json(params)
                r = HTTP.request(
                    method,
                    url,
                    headers,
                    body,
                    )
            end
        end
        return nothing
    end

    function _generate_new_repo_description(
            params::AbstractDict,
            )::String
        source_url::String = params[:source_url]
        when::TimeZones.ZonedDateTime = params[:when]
        time_zone::TimeZones.TimeZone = params[:time_zone]
        by::String = strip(string("@", _gitlab_username))

        new_description::String = Utils.default_repo_description(
            ;
            from = source_url,
            when = when,
            time_zone = time_zone,
            by = by,
            )

        return new_description
    end

    function _update_repo_description(params::AbstractDict)::Nothing
        repo_name::String = strip(params[:repo_name])
        new_repo_description = strip(params[:new_repo_description])
        _create_repo(
            Dict(
                :repo_name => repo_name,
                ),
            )
        repo_name_without_org::String = _repo_name_without_org(
            ;
            repo = repo_name,
            org = _gitlab_group,
            )

        method_1 = "GET"
        url_1 = string(
            "https://gitlab.com/api/v4/",
            "projects/$(_gitlab_group)%2F$(repo_name)",
            )
        headers_1 = Dict(
            "PRIVATE-TOKEN" => gitlab_bot_personal_access_token,
            )
        http_request_1 = () -> HTTP.request(
            method_1,
            url_1,
            headers_1,
            )
        r_1 = Utils.retry_function_until_success(
            http_request_1;
            max_attempts = 10,
            seconds_to_wait_between_attempts = 180,
        )
        r_body_1 = String(r_1.body)
        parsed_body_1 = JSON.parse(r_body_1)
        repo_id = parsed_body_1["id"]

        method_2 = "PUT"
        url_2 = string(
            "https://gitlab.com/api/v4/",
            "projects/$(repo_id)",
            )
        headers_2 = Dict(
            "PRIVATE-TOKEN" => gitlab_bot_personal_access_token,
            "content-type" => "application/json",
            )
        params_2 = Dict(
            "description" => new_repo_description,
            )
        body_2 = JSON.json(params_2)
        @info("Attempting to update repo description on GitLab...")
        http_request_2 = () -> HTTP.request(
            method_2,
            url_2,
            headers_2,
            body_2,
            )
        r_2 = Utils.retry_function_until_success(
            http_request_2;
            max_attempts = 10,
            seconds_to_wait_between_attempts = 180,
            )
        @info("Successfully updated repo description on GitLab")
        return nothing
    end

    function _list_all_repos()::Vector{String}
        @info("Loading the list of all of repos in my group")
        repo_name_list::Vector{String} = String[]
        need_to_continue = true
        current_page_number = 1
        method = "GET"
        my_group_id = _get_namespace_id_for_my_group()
        headers = Dict(
            "PRIVATE-TOKEN" => gitlab_bot_personal_access_token,
            )
        url = ""
        while need_to_continue
            @debug("current_page_number: ", current_page_number,)
            url = string(
                "https://gitlab.com/api/v4/groups/$(my_group_id)/projects",
                "?per_page=100&page=$(current_page_number)&",
                )
            r = HTTP.request(
                method,
                url,
                headers,
                )
            r_body = String(r.body)
            parsed_body = JSON.parse(r_body)
            if length(parsed_body) == 0
                need_to_continue = false
            else
                need_to_continue = true
                current_page_number += 1
                for i = 1:length(parsed_body)
                    repo_dict = parsed_body[i]
                    repo_name = repo_dict["name"]
                    if repo_name in repo_name_list
                        @debug(
                            string("already have this repo"),
                            repo_name,
                        )
                    else
                        push!(repo_name_list, repo_name)
                    end
                end
            end
        end
        sort!(repo_name_list)
        unique!(repo_name_list)
        sort!(repo_name_list)
        return repo_name_list
    end

    function _get_src_url(
            ;
            repo_name::String,
            credentials::Symbol,
            )::String
        repo_name_without_org::String = _repo_name_without_org(
            ;
            repo = repo_name,
            org = _gitlab_group,
            )
        result::String = ""
        if credentials == :with_auth
            result = string(
                "https://",
                _gitlab_username,
                ":",
                _gitlab_bot_personal_access_token,
                "@",
                "gitlab.com/",
                _gitlab_group,
                "/",
                repo_name_without_org,
                )
        elseif credentials == :with_redacted_auth
            result = string(
                "https://",
                _gitlab_username,
                ":",
                "*****",
                "@",
                "gitlab.com/",
                _gitlab_group,
                "/",
                repo_name_without_org,
                )
        elseif credentials == :without_auth
            result =string(
                "https://",
                "gitlab.com/",
                _gitlab_group,
                "/",
                repo_name_without_org,
                )
        else
            delayederror("$(credentials) is not a supported value for credentials")
        end
        return result
    end

    function _gitlab_provider(task::Symbol)::Function
        if task == :list_all_repos
            return _list_all_repos
        elseif task == :get_src_url
            return _get_src_url
        else
            delayederror("$(task) is not a valid task")
        end
    end

    return _gitlab_provider
end

end # End submodule Snapshots.Hosts.GitLabSrcHost

##### End of file
