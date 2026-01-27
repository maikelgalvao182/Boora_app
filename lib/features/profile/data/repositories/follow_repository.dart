import 'package:partiu/features/profile/data/datasources/follow_remote_datasource.dart';

class FollowRepository {
  final FollowRemoteDataSource _dataSource = FollowRemoteDataSource();

  Future<void> followUser(String targetUid) => _dataSource.followUser(targetUid);
  
  Future<void> unfollowUser(String targetUid) => _dataSource.unfollowUser(targetUid);
  
  Stream<bool> isFollowing(String myUid, String targetUid) => 
      _dataSource.isFollowing(myUid, targetUid);
}
