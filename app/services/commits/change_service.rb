module Commits
  class ChangeService < ::BaseService
    class ValidationError < StandardError; end
    class ChangeError < StandardError; end

    def execute
      @start_project = params[:start_project] || @project
      @start_branch = params[:start_branch]
      @target_branch = params[:target_branch]
      @commit = params[:commit]
      @create_merge_request = params[:create_merge_request].present?

      check_push_permissions unless @create_merge_request
      commit
    rescue Repository::CommitError, Gitlab::Git::Repository::InvalidBlobName, GitHooksService::PreReceiveError,
           ValidationError, ChangeError => ex
      error(ex.message)
    end

    private

    def action_zh(action)
      case action
      when :revert
        "撤销"
      when :cherry_pick
        "挑选"
      else
        action.to_s.dasherize
      end
    end

    def commit
      raise NotImplementedError
    end

    def commit_change(action)
      raise NotImplementedError unless repository.respond_to?(action)

      if @create_merge_request
        into = @commit.public_send("#{action}_branch_name")
        tree_branch = @start_branch
      else
        into = tree_branch = @target_branch
      end

      tree_id = repository.public_send(
        "check_#{action}_content", @commit, tree_branch)

      if tree_id
        validate_target_branch(into) if @create_merge_request

        repository.public_send(
          action,
          current_user,
          @commit,
          into,
          tree_id,
          start_project: @start_project,
          start_branch_name: @start_branch)

        success
      else
        error_msg = "很抱歉，我们无法自动 #{action_zh(action)} 此 #{@commit.change_type_title(current_user)} 。
                     它可能已经被 #{action_zh(action)}, 或者最近的提交已经更新了其中的某些内容。"
        raise ChangeError, error_msg
      end
    end

    def check_push_permissions
      allowed = ::Gitlab::UserAccess.new(current_user, project: project).can_push_to_branch?(@target_branch)

      unless allowed
        raise ValidationError.new('你不允许推送到此分支')
      end

      true
    end

    def validate_target_branch(new_branch)
      # Temporary branch exists and contains the change commit
      return if repository.find_branch(new_branch)

      result = ValidateNewBranchService.new(@project, current_user)
        .execute(new_branch)

      if result[:status] == :error
        raise ChangeError, "创建源分支时出错: #{result[:message]}"
      end
    end
  end
end
