class Sandbox
  def safe(level=4, limit=1)
    result = nil
    t = Thread.start {
      $SAFE = level
      result = yield
    }
    t.join(limit)
    t.kill
    result
  end
end
