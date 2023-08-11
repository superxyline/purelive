import 'package:supabase_flutter/supabase_flutter.dart';

class SupBaseManager {
  final String supabaseUrl = 'https://izqkszjbjoumibcoldzk.supabase.co';
  final String supabaseKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Iml6cWtzempiam91bWliY29sZHprIiwicm9sZSI6ImFub24iLCJpYXQiOjE2OTE3MjU0MzgsImV4cCI6MjAwNzMwMTQzOH0.9tOWVb3hLzdRpGazU9A84nCns9p2DhvimSJenhNPfWU';
  static late SupBaseManager _instance;
  SupBaseManager._internal();
  late Supabase supabase;

  SupabaseClient get client => Supabase.instance.client;
  //单例模式，只创建一次实例
  static SupBaseManager getInstance() {
    _instance = SupBaseManager._internal();
    return _instance;
  }

  SupBaseManager();
  Future<Supabase> initial() async {
    return await Supabase.initialize(url: supabaseUrl, anonKey: supabaseKey);
  }
}
