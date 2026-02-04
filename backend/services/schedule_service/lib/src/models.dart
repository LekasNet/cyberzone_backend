class AvailabilitySlot {
  final String id;
  final String userId;
  final String date;
  final String timeFrom;
  final String timeTo;

  AvailabilitySlot({
    required this.id,
    required this.userId,
    required this.date,
    required this.timeFrom,
    required this.timeTo,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'date': date,
        'timeFrom': timeFrom,
        'timeTo': timeTo,
      };
}
