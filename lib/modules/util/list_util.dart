
import 'dart:math';

class ListUtil<T> {

  /// 切分list
  List<List<T>> subList(List<T> list, int size){
    if(list.isEmpty) {
      return List.empty();
    }
    List<List<T>> rs = [];
    for (var i = 0; i < list.length; i += size) {
      var end = min(i + size, list.length);
      var subList = list.sublist(i, end);
      rs.add(subList);
    }
    return rs;
  }

}
