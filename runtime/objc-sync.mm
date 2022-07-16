/*
 * Copyright (c) 1999-2007 Apple Inc.  All Rights Reserved.
 * 
 * @APPLE_LICENSE_HEADER_START@
 * 
 * This file contains Original Code and/or Modifications of Original Code
 * as defined in and that are subject to the Apple Public Source License
 * Version 2.0 (the 'License'). You may not use this file except in
 * compliance with the License. Please obtain a copy of the License at
 * http://www.opensource.apple.com/apsl/ and read it before using this
 * file.
 * 
 * The Original Code and all software distributed under the License are
 * distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE, QUIET ENJOYMENT OR NON-INFRINGEMENT.
 * Please see the License for the specific language governing rights and
 * limitations under the License.
 * 
 * @APPLE_LICENSE_HEADER_END@
 */

#include "objc-private.h"
#include "objc-sync.h"

//
// Allocate a lock only when needed.  Since few locks are needed at any point
// in time, keep them on a single list.
//
/// @synchronized 锁
/// SyncData 单向链表的数据结构
typedef struct alignas(CacheLineSize) SyncData {
    struct SyncData* nextData; //下个节点
    DisguisedPtr<objc_object> object; //传入对象的封装 (DisguisedPtr关联对象也有)
    int32_t threadCount;  // number of THREADS using this block; 使用这个block(被加锁的代码块/对象)的线程数量,对象被几条线程加锁了
    recursive_mutex_t mutex; //recursive递归锁
} SyncData;

typedef struct {
    SyncData *data; //需要加锁的
    unsigned int lockCount;  // number of times THIS THREAD locked this block; 这个线程加锁的次数
} SyncCacheItem;

typedef struct SyncCache {
    unsigned int allocated;
    unsigned int used;
    SyncCacheItem list[0];
} SyncCache;

/*
  Fast cache: two fixed pthread keys store a single SyncCacheItem. 
  This avoids malloc of the SyncCache for threads that only synchronize 
  a single object at a time.
  SYNC_DATA_DIRECT_KEY  == SyncCacheItem.data
  SYNC_COUNT_DIRECT_KEY == SyncCacheItem.lockCount
 */

struct SyncList {
    SyncData *data;
    spinlock_t lock; //锁

    constexpr SyncList() : data(nil), lock(fork_unsafe_lock) { }
};

// Use multiple parallel lists to decrease contention among unrelated objects.
#define LOCK_FOR_OBJ(obj) sDataLists[obj].lock
#define LIST_FOR_OBJ(obj) sDataLists[obj].data
static StripedMap<SyncList> sDataLists; //全局静态唯一的哈希表


enum usage { ACQUIRE, RELEASE, CHECK };

static SyncCache *fetch_cache(bool create)
{
    _objc_pthread_data *data; //TLS中存了synchronize锁
    
    data = _objc_fetch_pthread_data(create);//取得TLS数据
    if (!data) return NULL;

    if (!data->syncCache) {
        if (!create) {
            return NULL;
        } else {
            int count = 4;
            data->syncCache = (SyncCache *)
                calloc(1, sizeof(SyncCache) + count*sizeof(SyncCacheItem));
            data->syncCache->allocated = count;
        }
    }

    // Make sure there's at least one open slot in the list.
    if (data->syncCache->allocated == data->syncCache->used) { //容量已满
        data->syncCache->allocated *= 2; //2倍扩容
        data->syncCache = (SyncCache *)
            realloc(data->syncCache, sizeof(SyncCache) 
                    + data->syncCache->allocated * sizeof(SyncCacheItem)); //重新开辟存储空间
    }

    return data->syncCache;//返回缓存数据
}


void _destroySyncCache(struct SyncCache *cache)
{
    if (cache) free(cache);
}


static SyncData* id2data(id object, enum usage why)
{
    spinlock_t *lockp = &LOCK_FOR_OBJ(object);//遍历StripedMap时加的锁
    SyncData **listp = &LIST_FOR_OBJ(object);//二级指针,链表的头节点指针
    SyncData* result = NULL;

    /// MARK: 检查快速缓存
#if SUPPORT_DIRECT_THREAD_KEYS
    // Check per-thread single-entry fast cache for matching object 检查每个线程的单条目快速缓存是否匹配对象.
    // 检查当前线程的TLS,寻找匹配的对象; 快速缓存中只存了一个SyncData, 不需要遍历查找,所以速度快.
    bool fastCacheOccupied = NO;
    SyncData *data = (SyncData *)tls_get_direct(SYNC_DATA_DIRECT_KEY);
    if (data) {
        fastCacheOccupied = YES; //找到了data数据

        if (data->object == object) { //对比快速缓存里的数据是否和当前需要加锁的对象相同
            // Found a match in fast cache.
            uintptr_t lockCount;

            result = data;
            lockCount = (uintptr_t)tls_get_direct(SYNC_COUNT_DIRECT_KEY);
            if (result->threadCount <= 0  ||  lockCount <= 0) {
                _objc_fatal("id2data fastcache is buggy");
            }

            switch(why) {
            case ACQUIRE: {
                lockCount++; //上锁次数+1
                tls_set_direct(SYNC_COUNT_DIRECT_KEY, (void*)lockCount);
                break;
            }
            case RELEASE:
                lockCount--; //上锁次数-1
                tls_set_direct(SYNC_COUNT_DIRECT_KEY, (void*)lockCount);
                if (lockCount == 0) { //次数为0时
                    // remove from fast cache
                    tls_set_direct(SYNC_DATA_DIRECT_KEY, NULL);//TLS中移除缓存
                    // atomic because may collide with concurrent ACQUIRE
                    OSAtomicDecrement32Barrier(&result->threadCount);//原子性操作,threadCount减1
                }
                break;
            case CHECK:
                // do nothing
                break;
            }

            return result;
        }
    }
#endif

    /// MARK: 检查TLS缓存
    // Check per-thread cache of already-owned locks for matching object 检查已拥有锁的每个线程缓存，以查找匹配的对象.
    //检查每个线程的cache(TLS:线程的局部私有存储空间),
    SyncCache *cache = fetch_cache(NO); //获取TLS缓存
    if (cache) {
        unsigned int i;
        for (i = 0; i < cache->used; i++) {
            SyncCacheItem *item = &cache->list[i]; //遍历缓存中的item数组
            if (item->data->object != object) continue;//object对比

            // Found a match.
            result = item->data; // 找到了一样的object, 赋给result
            if (result->threadCount <= 0  ||  item->lockCount <= 0) {
                _objc_fatal("id2data cache is buggy");//容错
            }
                
            switch(why) {
            case ACQUIRE://加锁
                item->lockCount++;//当前线程 加锁的次数+1
                break;
            case RELEASE://解锁
                item->lockCount--;//当前线程 加锁的次数-1
                if (item->lockCount == 0) { //次数为0了,说明当前线程完全解锁了
                    // remove from per-thread cache ;从线程缓存中移除这个item
                    cache->list[i] = cache->list[--cache->used];
                    // atomic because may collide with concurrent ACQUIRE
                    OSAtomicDecrement32Barrier(&result->threadCount);//线程数量-1
                }
                break;
            case CHECK:
                // do nothing
                break;
            }

            return result;
        }
    }

    /// MARK: 线程缓存没有数据,遍历列表
    /// 走完了上面流程, TLS里面没有找到对应数据, 就遍历链表中找, 从8/64张表中找
    /// 这条线程是第一次对这个对象加锁, 如果能在链表中找到匹配对象,说明这个对象被别的线程加锁了.
    // Thread cache didn't find anything.
    // Walk in-use list looking for matching object
    // Spinlock prevents multiple threads from creating multiple 
    // locks for the same new object.
    // We could keep the nodes in some hash table if we find that there are
    // more than 20 or so distinct locks active, but we don't do that now.
    
    lockp->lock(); //遍历列表,自己加一把锁

    {
        SyncData* p;
        SyncData* firstUnused = NULL;
        for (p = *listp; p != NULL; p = p->nextData) {//listp链表的头指针, 遍历链表每个节点
            if ( p->object == object ) {
                result = p;//找到了匹配对象
                // atomic because may collide with concurrent RELEASE
                OSAtomicIncrement32Barrier(&result->threadCount);//原子+1, 因为前面流程都没有找到,这里是第一次
                goto done;
            }
            if ( (firstUnused == NULL) && (p->threadCount == 0) )//对象没有加过锁
                firstUnused = p;
        }
    
        // no SyncData currently associated with object
        if ( (why == RELEASE) || (why == CHECK) )
            goto done;
    
        // an unused one was found, use it//对象没有加过锁
        if ( firstUnused != NULL ) {
            result = firstUnused;
            result->object = (objc_object *)object;
            result->threadCount = 1;
            goto done;
        }
    }
    
    /// MARK: 所有线程对这个对象都没有加过锁 synchronized
    /// 缓存和链表都没有, 第一次加锁, 初始化连新的链表, 分配一个新的SyncData并添加到列表中。
    // Allocate a new SyncData and add to list.
    // XXX allocating memory with a global lock held is bad practice,
    // might be worth releasing the lock, allocating, and searching again.
    // But since we never free these guys we won't be stuck in allocation very often.
    posix_memalign((void **)&result, alignof(SyncData), sizeof(SyncData));
    result->object = (objc_object *)object;
    result->threadCount = 1;
    new (&result->mutex) recursive_mutex_t(fork_unsafe_lock); //新建一把锁
    result->nextData = *listp;
    *listp = result; // 设为链表头结点
    
    // MARK: done 设置缓存
 done:
    lockp->unlock();
    if (result) {
        // Only new ACQUIRE should get here.
        // All RELEASE and CHECK and recursive ACQUIRE are 
        // handled by the per-thread caches above.
        if (why == RELEASE) {
            // Probably some thread is incorrectly exiting 
            // while the object is held by another thread.
            return nil; //已经解锁了
        }
        if (why != ACQUIRE) _objc_fatal("id2data is buggy");
        if (result->object != object) _objc_fatal("id2data is buggy");

#if SUPPORT_DIRECT_THREAD_KEYS //支持快速缓存
        if (!fastCacheOccupied) { //判断快速缓存有没有数据
            // Save in fast thread cache, 没有数据则设置快速缓存数据到TLS
            tls_set_direct(SYNC_DATA_DIRECT_KEY, result);
            tls_set_direct(SYNC_COUNT_DIRECT_KEY, (void*)1);
        } else 
#endif
        {
            // Save in thread cache 有快速缓存数据, 更新数据到cache缓存
            if (!cache) cache = fetch_cache(YES);
            cache->list[cache->used].data = result; //存到线程的缓存中
            cache->list[cache->used].lockCount = 1;
            cache->used++;
        }
    }

    return result;
}


BREAKPOINT_FUNCTION(
    void objc_sync_nil(void)
);

/**ji: objc_sync_enter */
// Begin synchronizing on 'obj'. 
// Allocates recursive mutex associated with 'obj' if needed.
// Returns OBJC_SYNC_SUCCESS once lock is acquired.  
int objc_sync_enter(id obj)
{
    int result = OBJC_SYNC_SUCCESS;

    if (obj) {
        SyncData* data = id2data(obj, ACQUIRE);
        ASSERT(data);
        data->mutex.lock();//加锁
    } else {
        // @synchronized(nil) does nothing
        if (DebugNilSync) {
            _objc_inform("NIL SYNC DEBUG: @synchronized(nil); set a breakpoint on objc_sync_nil to debug");
        }
        objc_sync_nil();
    }

    return result;
}

BOOL objc_sync_try_enter(id obj)
{
    BOOL result = YES;

    if (obj) {
        SyncData* data = id2data(obj, ACQUIRE);
        ASSERT(data);
        result = data->mutex.tryLock();
    } else {
        // @synchronized(nil) does nothing
        if (DebugNilSync) {
            _objc_inform("NIL SYNC DEBUG: @synchronized(nil); set a breakpoint on objc_sync_nil to debug");
        }
        objc_sync_nil();
    }

    return result;
}

/**ji: objc_sync_exit */
// End synchronizing on 'obj'. 
// Returns OBJC_SYNC_SUCCESS or OBJC_SYNC_NOT_OWNING_THREAD_ERROR
int objc_sync_exit(id obj)
{
    int result = OBJC_SYNC_SUCCESS;
    
    if (obj) {
        SyncData* data = id2data(obj, RELEASE); 
        if (!data) {
            result = OBJC_SYNC_NOT_OWNING_THREAD_ERROR;
        } else {
            bool okay = data->mutex.tryUnlock();//解锁
            if (!okay) {
                result = OBJC_SYNC_NOT_OWNING_THREAD_ERROR;
            }
        }
    } else {
        // @synchronized(nil) does nothing
    }
	

    return result;
}

