import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

import '../../../auto_route.dart';

typedef AnimatedIndexedStackBuilder = Widget Function(BuildContext context, Widget child, Animation<double> animation);
typedef AutoTabsBuilder = Widget Function(BuildContext context, List<Widget> children, TabsRouter tabsRouter);
typedef AutoTabsPageViewBuilder = Widget Function(BuildContext context, Widget child);
typedef OnNavigationChanged = Function(TabsRouter tabsRouter);

class AutoTabsRouter extends StatefulWidget {
  final AnimatedIndexedStackBuilder? builder;
  final List<PageRouteInfo> routes;
  final Duration duration;
  final Curve curve;
  final bool lazyLoad;
  final NavigatorObserversBuilder navigatorObservers;
  final bool inheritNavigatorObservers;
  final int? _activeIndex;
  final bool declarative;
  final OnTabNavigateCallBack? onNavigate;

  // if activeIndex != homeIndex
  // set activeIndex to homeIndex
  // else pop parent
  final int homeIndex;

  const AutoTabsRouter({
    Key? key,
    required this.routes,
    this.lazyLoad = true,
    this.duration = const Duration(milliseconds: 300),
    this.curve = Curves.ease,
    this.builder,
    this.homeIndex = -1,
    this.inheritNavigatorObservers = true,
    this.navigatorObservers = AutoRouterDelegate.defaultNavigatorObserversBuilder,
  })  : declarative = false,
        _activeIndex = null,
        onNavigate = null,
        super(key: key);

  factory AutoTabsRouter.pageView({
    Key? key,
    required List<PageRouteInfo> routes,
    AutoTabsPageViewBuilder? builder,
    int homeIndex,
    bool animatePageTransition,
    Duration duration,
    Curve curve,
    bool inheritNavigatorObservers,
    NavigatorObserversBuilder navigatorObservers,
  }) = _AutoTabsRouterPageView;

  factory AutoTabsRouter.builder({
    Key? key,
    required List<PageRouteInfo> routes,
    required AutoTabsBuilder builder,
    OnNavigationChanged? onNavigate,
    OnNavigationChanged? onRouterReady,
    int homeIndex,
    bool inheritNavigatorObservers,
    NavigatorObserversBuilder navigatorObservers,
  }) = _AutoTabsRouterBuilder;

  const AutoTabsRouter.declarative({
    Key? key,
    required this.routes,
    this.lazyLoad = true,
    required int activeIndex,
    this.duration = const Duration(milliseconds: 300),
    this.curve = Curves.ease,
    this.builder,
    this.onNavigate,
    this.homeIndex = -1,
    this.inheritNavigatorObservers = true,
    this.navigatorObservers = AutoRouterDelegate.defaultNavigatorObserversBuilder,
  })  : declarative = true,
        _activeIndex = activeIndex,
        super(key: key);

  @override
  AutoTabsRouterState createState() => AutoTabsRouterState();

  static TabsRouter of(BuildContext context, {bool watch = false}) {
    var scope = TabsRouterScope.of(context, watch: watch);
    assert(() {
      if (scope == null) {
        throw FlutterError('AutoTabsRouter operation requested with a context that does not include an AutoTabsRouter.\n'
            'The context used to retrieve the AutoTabsRouter must be that of a widget that '
            'is a descendant of an AutoTabsRouter widget.');
      }
      return true;
    }());
    return scope!.controller;
  }
}

class AutoTabsRouterState extends State<AutoTabsRouter> with SingleTickerProviderStateMixin {
  TabsRouter? _controller;
  late AnimationController _animationController;
  late Animation<double> _animation;
  int _index = 0;
  late RoutingController _parentController;

  TabsRouter? get controller => _controller;
  late int _tabsHash;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _animation = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: widget.curve,
      ),
    );
    _tabsHash = ListEquality().hash(widget.routes);
  }

  late List<NavigatorObserver> _navigatorObservers;
  late NavigatorObserversBuilder _inheritableObserversBuilder;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final parentRoute = RouteData.of(context);
    if (_controller == null) {
      final parentScope = RouterScope.of(context, watch: true);
      _inheritableObserversBuilder = () {
        var observers = widget.navigatorObservers();
        if (!widget.inheritNavigatorObservers) {
          return observers;
        }
        var inheritedObservers = parentScope.inheritableObserversBuilder();
        return inheritedObservers + observers;
      };
      _navigatorObservers = _inheritableObserversBuilder();
      _parentController = parentScope.controller;
      _controller = TabsRouter(
        parent: _parentController,
        key: parentRoute.key,
        homeIndex: widget.homeIndex,
        managedByWidget: widget.declarative,
        initialIndex: widget._activeIndex,
        routeData: parentRoute,
        onNavigate: widget.onNavigate,
        routeCollection: _parentController.routeCollection.subCollectionOf(
          parentRoute.name,
        ),
        pageBuilder: _parentController.pageBuilder,
      );
      _parentController.attachChildController(_controller!);
      _setupController();
    }
  }

  void _setupController() {
    assert(_controller != null);
    _controller!.setupRoutes(widget.routes);
    _index = _controller!.activeIndex;
    _animationController.value = 1.0;
    _controller!.addListener(() {
      if (widget._activeIndex == null && _controller!.activeIndex != _index) {
        setState(() {
          _index = _controller!.activeIndex;
        });
        _animationController.forward(from: 0.0);
      } else if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    super.dispose();
    if (_controller != null) {
      _controller!.dispose();
      _parentController.removeChildController(_controller!);
      _controller = null;
    }
  }

  @override
  void didUpdateWidget(covariant AutoTabsRouter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!ListEquality().equals(widget.routes, oldWidget.routes)) {
      _controller!.replaceAll(widget.routes, oldWidget.routes[_index]);
      _tabsHash = ListEquality().hash(widget.routes);
      setState(() {
        _index = _controller!.activeIndex;
      });
    }
    if (widget.declarative && widget._activeIndex != oldWidget._activeIndex) {
      _animationController.value = 1.0;
      _index = widget._activeIndex!;
      _animationController.forward(from: 0.0);
      _controller!.setActiveIndex(_index, notify: false);
      WidgetsBinding.instance?.addPostFrameCallback((_) {
        AutoRouterDelegate.of(context).notifyUrlChanged();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    assert(_controller != null);
    final stack = _controller!.stack;
    final builder = widget.builder ?? _defaultBuilder;
    final stateHash = controller!.stateHash;

    final builderChild = stack.isEmpty
        ? Container(color: Theme.of(context).scaffoldBackgroundColor)
        : _IndexedStackBuilder(
            activeIndex: _index,
            tabsHash: _tabsHash,
            lazyLoad: widget.lazyLoad,
            animation: _animation,
            navigatorObservers: _navigatorObservers,
            itemBuilder: (BuildContext context, int index) {
              return stack[index].buildPage(context);
            },
            stack: stack,
          );

    return RouterScope(
      controller: _controller!,
      inheritableObserversBuilder: _inheritableObserversBuilder,
      stateHash: stateHash,
      navigatorObservers: _navigatorObservers,
      child: TabsRouterScope(
        controller: _controller!,
        stateHash: stateHash,
        child: AnimatedBuilder(
          animation: _animation,
          builder: (context, child) => builder(
            context,
            child ?? builderChild,
            _animation,
          ),
          child: builderChild,
        ),
      ),
    );
  }

  Widget _defaultBuilder(_, child, animation) {
    return FadeTransition(opacity: animation, child: child);
  }
}

class _IndexedStackBuilder extends StatefulWidget {
  const _IndexedStackBuilder({
    Key? key,
    required this.activeIndex,
    required this.itemBuilder,
    required this.navigatorObservers,
    required this.stack,
    required this.lazyLoad,
    required this.tabsHash,
    required this.animation,
  }) : super(key: key);

  final int activeIndex;
  final IndexedWidgetBuilder itemBuilder;
  final bool lazyLoad;
  final List<AutoRoutePage> stack;
  final List<NavigatorObserver> navigatorObservers;
  final int tabsHash;
  final Animation<double> animation;

  @override
  _IndexedStackBuilderState createState() => _IndexedStackBuilderState();
}

class _IndexedStackBuilderState extends State<_IndexedStackBuilder> with _RouteAwareTabsMixin<_IndexedStackBuilder> {
  final _dummyWidget = const SizedBox.shrink();
  final _initializedPagesTracker = <int, bool>{};

  @override
  List<RouteMatch> get routes => widget.stack.map((e) => e.routeData.route).toList();

  @override
  List<NavigatorObserver> get observers => widget.navigatorObservers;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  void _setup() {
    for (var i = 0; i < widget.stack.length; ++i) {
      if (i == widget.activeIndex || !widget.lazyLoad) {
        _initializedPagesTracker[i] = true;
        _didInitTabRoute(i);
      } else {
        _initializedPagesTracker[i] = false;
      }
    }
  }

  @override
  void didUpdateWidget(_IndexedStackBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.tabsHash != oldWidget.tabsHash) {
      _initializedPagesTracker.clear();
      _setup();
      return;
    }
    if (widget.lazyLoad && _initializedPagesTracker[widget.activeIndex] != true) {
      _initializedPagesTracker[widget.activeIndex] = true;
      _didInitTabRoute(widget.activeIndex, oldWidget.activeIndex);
    } else if (widget.activeIndex != oldWidget.activeIndex) {
      _didChangeTabRoute(widget.activeIndex, oldWidget.activeIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      key: ValueKey(widget.tabsHash),
      index: widget.activeIndex,
      sizing: StackFit.expand,
      children: List.generate(
        widget.stack.length,
        (index) {
          if (!widget.stack[index].maintainState && index != widget.activeIndex) {
            _initializedPagesTracker[index] = false;
          }
          final isInitialized = _initializedPagesTracker[index] == true;
          return isInitialized ? widget.itemBuilder(context, index) : _dummyWidget;
        },
      ),
    );
  }
}



class _AutoTabsRouterPageView extends AutoTabsRouter {
  final AutoTabsPageViewBuilder? _pageViewModeBuilder;
  final bool animatePageTransition;

  const _AutoTabsRouterPageView({
    Key? key,
    required List<PageRouteInfo> routes,
    AutoTabsPageViewBuilder? builder,
    int homeIndex = -1,
    this.animatePageTransition = true,
    Duration duration = kTabScrollDuration,
    Curve curve = Curves.easeInOut,
    bool inheritNavigatorObservers = true,
    NavigatorObserversBuilder navigatorObservers = AutoRouterDelegate.defaultNavigatorObserversBuilder,
  })  : _pageViewModeBuilder = builder,
        super(
          key: key,
          routes: routes,
          homeIndex: homeIndex,
          duration: duration,
          curve: curve,
          navigatorObservers: navigatorObservers,
          inheritNavigatorObservers: inheritNavigatorObservers,
        );

  @override
  AutoTabsRouterPageViewState createState() => AutoTabsRouterPageViewState();
}

class AutoTabsRouterPageViewState extends AutoTabsRouterState with _RouteAwareTabsMixin<AutoTabsRouter> {
  late List<NavigatorObserver> _navigatorObservers;
  late NavigatorObserversBuilder _inheritableObserversBuilder;
  late PageController _pageController;

  @override
  void _setupController() {
    assert(_controller != null);
    _controller!.setupRoutes(widget.routes);
    _pageController = PageController(initialPage: _controller!.activeIndex);
    _didInitTabRoute(_controller!.activeIndex);
    _controller!.addListener(() {
      if (_controller!.activeIndex != _pageController.page) {
        _didChangeTabRoute(_controller!.activeIndex, _pageController.page?.toInt() ?? 0);
      }
      if (_controller!.activeIndex != _pageController.page?.round()) {
        if (typedWidget.animatePageTransition && _canAnimateTransition(_pageController.page, _controller!.activeIndex)) {
          _pageController.animateToPage(
            _controller!.activeIndex,
            duration: widget.duration,
            curve: widget.curve,
          );
        } else {
          _pageController.jumpToPage(_controller!.activeIndex);
        }
      } else if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void didUpdateWidget(covariant _AutoTabsRouterPageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!ListEquality().equals(widget.routes, oldWidget.routes)) {
      _controller!.replaceAll(widget.routes, oldWidget.routes[_pageController.page?.round() ?? 0]);
      _tabsHash = const ListEquality().hash(widget.routes);
      _pageController.jumpToPage(
        _controller!.activeIndex,
      );
    }
  }

  _AutoTabsRouterPageView get typedWidget => widget as _AutoTabsRouterPageView;

  @override
  Widget build(BuildContext context) {
    assert(_controller != null);
    final stack = _controller!.stack;
    final builder = typedWidget._pageViewModeBuilder ?? _defaultPageViewBuilder;
    final stateHash = controller!.stateHash;
    return RouterScope(
      controller: _controller!,
      inheritableObserversBuilder: _inheritableObserversBuilder,
      stateHash: stateHash,
      navigatorObservers: _navigatorObservers,
      child: TabsRouterScope(
        controller: _controller!,
        stateHash: stateHash,
        child: Builder(builder: (context) {
          return builder(
            context,
            PageView.builder(
              controller: _pageController,
              itemCount: stack.length,
              onPageChanged: _controller!.setActiveIndex,
              itemBuilder: (context, index) {
                return KeepAliveTab(
                  key: ValueKey(index),
                  page: stack[index],
                );
              },
            ),
          );
        }),
      ),
    );
  }

  Widget _defaultPageViewBuilder(_, Widget child) {
    return child;
  }

  // to make sure we don't animate to a page that's more than
  // one step away
  bool _canAnimateTransition(double? pageViewIndex, int activeIndex) {
    if (pageViewIndex == null) return false;
    return (pageViewIndex - activeIndex).abs() <= 1;
  }

  @override
  List<NavigatorObserver> get observers => _navigatorObservers;

  @override
  List<RouteMatch> get routes => _controller!.stackData.map((e) => e.route).toList();
}

class _AutoTabsRouterBuilder extends AutoTabsRouter {
  final AutoTabsBuilder _customBuilder;
  final OnNavigationChanged? _onChanged;
  final OnNavigationChanged? onRouterReady;

  const _AutoTabsRouterBuilder({
    Key? key,
    required List<PageRouteInfo> routes,
    OnNavigationChanged? onNavigate,
    this.onRouterReady,
    required AutoTabsBuilder builder,
    int homeIndex = -1,
    bool inheritNavigatorObservers = true,
    NavigatorObserversBuilder navigatorObservers = AutoRouterDelegate.defaultNavigatorObserversBuilder,
  })  : _customBuilder = builder,
        _onChanged = onNavigate,
        super(
          key: key,
          routes: routes,
          homeIndex: homeIndex,
          navigatorObservers: navigatorObservers,
          inheritNavigatorObservers: inheritNavigatorObservers,
        );

  @override
  _AutoTabsRouterBuilderState createState() => _AutoTabsRouterBuilderState();
}

class _AutoTabsRouterBuilderState extends AutoTabsRouterState with _RouteAwareTabsMixin<AutoTabsRouter> {
  @override
  void _setupController() {
    assert(_controller != null);
    _controller!.setupRoutes(widget.routes);
    typedWidget.onRouterReady?.call(_controller!);
    _didInitTabRoute(_controller!.activeIndex);
    _controller!.addListener(() {
      if (_controller!.activeIndex != _controller!.previousIndex) {
        _didChangeTabRoute(_controller!.activeIndex, _controller!.previousIndex ?? -1);
        typedWidget._onChanged?.call(_controller!);
      }
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void didUpdateWidget(covariant _AutoTabsRouterBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!ListEquality().equals(widget.routes, oldWidget.routes)) {
      _controller!.replaceAll(widget.routes, oldWidget.routes[_index]);
      _tabsHash = ListEquality().hash(widget.routes);
      typedWidget._onChanged?.call(_controller!);
    }
  }

  _AutoTabsRouterBuilder get typedWidget => widget as _AutoTabsRouterBuilder;

  @override
  Widget build(BuildContext context) {
    assert(_controller != null);
    final stack = _controller!.stack;
    final builder = typedWidget._customBuilder;
    final stateHash = controller!.stateHash;
    return RouterScope(
      controller: _controller!,
      inheritableObserversBuilder: _inheritableObserversBuilder,
      stateHash: stateHash,
      navigatorObservers: _navigatorObservers,
      child: TabsRouterScope(
        controller: _controller!,
        stateHash: stateHash,
        child: Builder(
            key: ValueKey(_tabsHash),
            builder: (context) {
              return builder(
                context,
                List.generate(
                  stack.length,
                  (index) => KeepAliveTab(
                    key: ValueKey(index),
                    page: stack[index],
                  ),
                ),
                _controller!,
              );
            }),
      ),
    );
  }

  @override
  List<NavigatorObserver> get observers => _navigatorObservers;

  @override
  List<RouteMatch> get routes => _controller!.stackData.map((e) => e.route).toList();
}

mixin _RouteAwareTabsMixin<T extends StatefulWidget> on State<T> {
  List<NavigatorObserver> get observers;

  List<RouteMatch> get routes;

  void _didInitTabRoute(int index, [int previous = -1]) {
    observers.whereType<AutoRouterObserver>().forEach((observer) {
      var previousRoute;
      if (previous != -1) {
        previousRoute = TabPageRoute(routeInfo: routes[previous], index: previous);
      }
      observer.didInitTabRoute(
        TabPageRoute(routeInfo: routes[index], index: index),
        previousRoute,
      );
    });
  }

  void _didChangeTabRoute(int index, int previous) {
    observers.whereType<AutoRouterObserver>().forEach((observer) {
      observer.didChangeTabRoute(
        TabPageRoute(routeInfo: routes[index], index: index),
        TabPageRoute(routeInfo: routes[previous], index: previous),
      );
    });
  }
}

class KeepAliveTab extends StatefulWidget {
  const KeepAliveTab({
    Key? key,
    required this.page,
  }) : super(key: key);
  final AutoRoutePage page;

  @override
  State<KeepAliveTab> createState() => _KeepAliveTabState();
}

class _KeepAliveTabState extends State<KeepAliveTab> with AutomaticKeepAliveClientMixin {
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.page.buildPage(context);
  }

  @override
  bool get wantKeepAlive => widget.page.maintainState;
}
