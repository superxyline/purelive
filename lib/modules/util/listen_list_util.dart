
import 'dart:async';

import 'package:get/get.dart';

final class ListenListUtil{

  static void clearStreamSubscriptionList(List<StreamSubscription> list){
    for(var s in list){
      s.cancel();
    }
    list.clear();
  }

  static void clearWorkerList(List<Worker> list){
    for(var s in list){
      s.dispose();
    }
    list.clear();
  }

}