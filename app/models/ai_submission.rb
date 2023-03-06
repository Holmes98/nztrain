class AiSubmission < ActiveRecord::Base

  belongs_to :ai_contest
  belongs_to :user

  scope :active, -> { where(:active => true) }

  def submit
    return false unless activate
    true
  end

  def judge
    ai_contest.submissions.active.each do |submission|
      next if submission.id == self.id
      (0...ai_contest.iterations).each do |iteration|
        begin
          game = AiContestGame.find_or_create_by_ai_contest_id_and_ai_submission_1_id_and_ai_submission_2_id_and_iteration(ai_contest.id, self.id, submission.id, iteration)
          #game = AiContestGame.where(:ai_contest_id => ai_contest.id, :ai_submission_1_id => self.id, :ai_submission_2_id => submission.id, :iteration => iteration)
          #if game.length==0
          #  game = AiContestGame.create(:ai_contest => ai_contest, :ai_submission_1 => self, :ai_submission_2 => submission, :iteration => iteration)
          #else
          #  game = game.first
          #end
          if game.record == nil
            game.judge
            game.save
          end
        rescue Exception
        end
        begin
          game = AiContestGame.find_or_create_by_ai_contest_id_and_ai_submission_1_id_and_ai_submission_2_id_and_iteration(ai_contest.id, submission.id, self.id, iteration)
          #game = AiContestGame.where(:ai_contest_id => ai_contest.id, :ai_submission_1_id => submission.id, :ai_submission_2_id => self.id, :iteration => iteration)
          #if game.length==0
          #  game = AiContestGame.create(:ai_contest => ai_contest, :ai_submission_1 => self, :ai_submission_2 => submission, :iteration => iteration)
          #else
          #  game = game.first
          #end
          if game.record == nil
            game.judge
            game.save
          end
        rescue Exception
        end
      end
    end
  end

  def source_file=(file)
    self.source = IO.read(file.path)
  end

  def deactivate
    self.active = false
    save
  end

  def activate
    self.active = true
    return false unless save
    if user_id != ai_contest.owner_id
      AiSubmission.update_all({:active => false}, ["user_id = ? AND ai_contest_id = ? AND id != ?", user, ai_contest_id, id])
    end
    #Rails.env == 'test' ? self.judge : spawn(:nice => 10) { self.judge } # use background queue
    true
  end

  def rejudge
    #AiContestGame.update_all({:record => nil, :score_1 => nil, :score_2 => nil}, :ai_submission_1_id => id)
    #AiContestGame.update_all({:record => nil, :score_1 => nil, :score_2 => nil}, :ai_submission_2_id => id)
    AiContestGame.delete_all(:ai_submission_1_id => id)
    AiContestGame.delete_all(:ai_submission_2_id => id)
    
    judge if self.active
  end
end
