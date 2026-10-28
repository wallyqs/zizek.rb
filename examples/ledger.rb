# frozen_string_literal: true

require "zizek"

module LedgerExample
  LIMIT = 1_000_000
  PORTABLE_LEDGER_FAILURE =
    "AXicVYyxCQAgEAMvYmXtILr/cipq+C/ChRykA4K2w4eohyMuWU0ryUWvXBSLdK4FQmgBCA=="

  class Ledger
    attr_reader :balances

    def initialize
      @balances = {}
    end

    def credit(account, amount)
      balances[account] = balances.fetch(account, 0) + amount
    end

    def debit(account, amount)
      balances[account] = balances.fetch(account, 0) - amount
    end

    def transfer(source, destination, amount)
      source_balance = balances.fetch(source, 0)
      return unless source != destination && amount - source_balance <= 1

      debit(source, amount)
      credit(destination, amount)
    end
  end

  class LedgerTest
    def initialize(accounts)
      @ledger = Ledger.new
      @accounts = accounts
    end

    def create_account(test_case)
      account = test_case.draw(Zizek::Generators.text.min_size(1))
      test_case.note("create account #{account.inspect}")
      @accounts.add(test_case, account)
    end

    def credit(test_case)
      account = test_case.draw(@accounts.values_reusable)
      amount = test_case.draw(Zizek::Generators.integers.min_value(0).max_value(LIMIT))
      test_case.note("credit #{account.inspect} with #{amount}")
      @ledger.credit(account, amount)
    end

    def transfer(test_case)
      source = test_case.draw(@accounts.values_reusable)
      destination = test_case.draw(@accounts.values_reusable)
      amount = test_case.draw(Zizek::Generators.integers.min_value(0).max_value(LIMIT))
      test_case.note("transfer #{amount} from #{source.inspect} to #{destination.inspect}")
      @ledger.transfer(source, destination, amount)
    end

    def nonnegative_balances(_test_case)
      @ledger.balances.each do |account, balance|
        raise "account #{account.inspect} has negative balance #{balance}" if balance.negative?
      end
    end

    def rules
      [
        Zizek::Stateful::Rule.new("create_account", ->(machine, test_case) { machine.create_account(test_case) }),
        Zizek::Stateful::Rule.new("credit", ->(machine, test_case) { machine.credit(test_case) }),
        Zizek::Stateful::Rule.new("transfer", ->(machine, test_case) { machine.transfer(test_case) })
      ]
    end

    def invariants
      [
        Zizek::Stateful::Rule.new(
          "nonnegative_balances",
          ->(machine, test_case) { machine.nonnegative_balances(test_case) }
        )
      ]
    end
  end

  module_function

  def property(test_case)
    Zizek::Stateful.run(
      LedgerTest.new(Zizek::Stateful.pool(test_case)),
      test_case
    )
  end

  def find_and_replay_bug
    found =
      begin
        Zizek.check(method(:property), examples: 2_000, seed: 1)
        raise "the ledger off-by-one bug should be discovered"
      rescue Zizek::Failure => failure
        raise unless failure.property_cause.message.include?("negative balance")

        failure
      end

    begin
      Zizek.check(method(:property), reproduce: found.blob)
    rescue Zizek::Failure
      return found
    end
    raise "the shrunk ledger failure must replay"
  end
end

puts LedgerExample.find_and_replay_bug if $PROGRAM_NAME == __FILE__
