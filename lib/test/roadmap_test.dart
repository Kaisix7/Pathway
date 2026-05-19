// ...existing code...

  test('Progress is 0 when no tasks', () {
    List<Task> tasks = [];

    int done = tasks.where((t) => t.done).length;
    int total = tasks.length;

    double progress = total == 0 ? 0.0 : (done / total).clamp(0.0, 1.0);
    int percent = (progress * 100).round();

    expect(progress, 0.0);
    expect(percent, 0);
  });

  test('Progress is 1 when all tasks done', () {
    List<Task> tasks = [
      Task('Task 1', true),
      Task('Task 2', true),
    ];

    int done = tasks.where((t) => t.done).length;
    int total = tasks.length;

    double progress = total == 0 ? 0.0 : (done / total).clamp(0.0, 1.0);
    int percent = (progress * 100).round();

    expect(progress, 1.0);
    expect(percent, 100);
  });

  test('Progress is 0 when no tasks done', () {
    List<Task> tasks = [
      Task('Task 1', false),
      Task('Task 2', false),
    ];

    int done = tasks.where((t) => t.done).length;
    int total = tasks.length;

    double progress = total == 0 ? 0.0 : (done / total).clamp(0.0, 1.0);
    int percent = (progress * 100).round();

    expect(progress, 0.0);
    expect(percent, 0);
  });

  test('Toggle task from false to true', () {
    List<Task> tasks = [
      Task('Task 1', false),
    ];

    // Simulate toggle
    tasks[0].done = !tasks[0].done;

    int done = tasks.where((t) => t.done).length;
    int total = tasks.length;

    double progress = done / total;
    int percent = (progress * 100).round();

    expect(tasks[0].done, true);
    expect(progress, 1.0);
    expect(percent, 100);
  });

  test('Toggle task from true to false', () {
    List<Task> tasks = [
      Task('Task 1', true),
    ];

    // Simulate toggle
    tasks[0].done = !tasks[0].done;

    int done = tasks.where((t) => t.done).length;
    int total = tasks.length;

    double progress = done / total;
    int percent = (progress * 100).round();

    expect(tasks[0].done, false);
    expect(progress, 0.0);
    expect(percent, 0);
  });

// ...existing code...