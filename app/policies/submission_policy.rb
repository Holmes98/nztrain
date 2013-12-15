class SubmissionPolicy < ApplicationPolicy

  class Scope < ApplicationPolicy::Scope
    def resolve
      if user.is_staff?
        scope.all
      else
        if user.competing?
          problem_set_ids = ContestRelations.where{ |contest_relations| contest_relations.user_id == user.id & contest_relations.started_at <= DateTime.now & contest_relations.finish_at > DateTime.now }.joins(:contest).select(:problem_set_id)
          return scope.joins(:problem).joins(:problem_sets).where(:problem => {:problem_sets => {:id => problem_set_ids }})
        else
          return scope.joins(:problem).where{ |submission| (submission.user_id == user.id) | (submission.problem.owner_id == user.id) }
        end
      end
    end
  end

  def index?
    true
  end

  def show?
    user.is_staff? or scope.where(:id => record.id).exists?
  end

  def rejudge?
    manage?
  end
end

