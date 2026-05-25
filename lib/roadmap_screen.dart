class _RoadmapScreenState extends State<RoadmapScreen> {
  double progress = 0.0;
  int percent = 0;

  @override
  void initState() {
    super.initState();
    updateProgress();
  }

  void updateProgress() {
    final int roadmapTotal = tasks.length;
    final int roadmapDone = tasks.where((task) => task.done).length;

    if (roadmapTotal == 0) {
      progress = 0.0;
    } else {
      progress = (roadmapDone / roadmapTotal).clamp(0.0, 1.0).toDouble();
    }

    percent = (progress * 100).round();
  }

  void toggleTask(int index) {
    setState(() {
      tasks[index].done = !tasks[index].done;
      updateProgress();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // ...existing code...
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Progress: $percent%',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: progress),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: tasks.length,
              itemBuilder: (context, index) {
                final task = tasks[index];

                return CheckboxListTile(
                  value: task.done,
                  onChanged: (_) => toggleTask(index),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(
                    task.title,
                    style: TextStyle(
                      decoration: task.done
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                    ),
                  ),
                  subtitle: Text(task.done ? 'Done' : 'Not done'),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}