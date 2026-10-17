import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:offlinetube/core/theme/app_theme.dart';
import 'package:offlinetube/features/navigation/helper.dart';

class LibraryEmptyState extends StatefulWidget {
  final TextEditingController searchController;
  final VoidCallback callSearch;
  const LibraryEmptyState({
    super.key,
    required this.searchController,
    required this.callSearch,
  });

  @override
  State<LibraryEmptyState> createState() => _LibraryEmptyStateState();
}

class _LibraryEmptyStateState extends State<LibraryEmptyState> {
  final FocusNode _focusNode = FocusNode();

  List<String> _suggestions = [];
  Future<void> getYoutubeSuggestions() async {
    try {
      if (widget.searchController.text.trim().isEmpty) {
        setState(() {
          _suggestions.clear();
          return;
        });
      }
      ;

      final uri = Uri.parse(
        'https://suggestqueries.google.com/complete/search'
        '?client=youtube&ds=yt&q=${Uri.encodeComponent(widget.searchController.text)}',
      );

      final response = await http.get(uri);

      if (response.statusCode != 200) {
        _suggestions.clear();
        return;
      }
      try {
        String body = response.body;

        // Remove JSONP wrapper:
        final start = body.indexOf('(');
        final end = body.lastIndexOf(')');

        if (start == -1 || end == -1) {
          _suggestions.clear();
          return;
        }

        body = body.substring(start + 1, end);

        final data = jsonDecode(body);

        setState(() {
          _suggestions = List<String>.from(
            data[1].map((item) => item[0].toString()),
          );
        });
      } catch (e) {
        print('Suggestion error: $e');
        _suggestions.clear();
        return;
      }
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(CupertinoIcons.globe),
              SizedBox(width: 10),
              Text('Internet not available'),
            ],
          ),
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    widget.searchController.addListener(getYoutubeSuggestions);
  }

  @override
  void dispose() {
    widget.searchController.removeListener(getYoutubeSuggestions);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            children: [
              // App branding
              Image.asset(
                'appicon.png',
                width: 88,
                height: 88,
                fit: BoxFit.contain,
              ),

              const SizedBox(height: 28),
              // Search field
              Row(
                children: [
                  Container(
                    margin: EdgeInsets.only(right: 15),
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    decoration: BoxDecoration(
                      color: Color(0xff272727),
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: Icon(CupertinoIcons.location),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(50),
                      child: TextField(
                        controller: widget.searchController,
                        focusNode: _focusNode,
                        onSubmitted: (value) {
                          widget.callSearch();
                        },
                        onTapOutside: (event) {
                          _focusNode.unfocus();
                        },
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: 'Search YouTube',
                          hintStyle: TextStyle(
                            color: colors.onSurfaceVariant,
                            fontSize: 18,
                          ),
                          filled: true,
                          fillColor: Color(0xff272727),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 14,
                            horizontal: 18,
                          ),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      widget.callSearch();
                    },
                    child: Container(
                      margin: EdgeInsets.only(left: 15),
                      padding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        color: Color(0xff272727),
                        borderRadius: BorderRadius.circular(50),
                      ),
                      child: Icon(CupertinoIcons.search),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 36),

              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(horizontal: 30, vertical: 30),
                decoration: BoxDecoration(
                  color: Color(0xff212121),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      if (widget.searchController.text.isEmpty) ...[
                        Text(
                          'Your library is empty',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.w400,
                            fontSize: 22,
                          ),
                        ),

                        const SizedBox(height: 10),

                        Text(
                          'Download your favorite videos to watch '
                          'anytime, anywhere, even without internet.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),

                        const SizedBox(height: 28),

                        // Add video action
                        ElevatedButton.icon(
                          onPressed: () {
                            openAddVideoModalBasic(context);
                          },
                          label: const Text(
                            'Add video',
                            style: TextStyle(fontSize: 13),
                          ),
                          style: ElevatedButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor: Color(0xff373737),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 35,
                              vertical: 16,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(50),
                            ),
                            elevation: 0,
                            textStyle: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ] else ...[
                        ..._suggestions.map((value) {
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                            ),
                            leading: const Icon(Icons.search),
                            title: Text(value),
                            onTap: () {
                              widget.searchController.text = value;
                              widget.callSearch();

                              setState(() {
                                _suggestions.clear();
                              });
                            },
                          );
                        }),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


    // return Center(
    //   child: Padding(
    //     padding: const EdgeInsets.symmetric(horizontal: 32),
    //     child: Column(
    //       mainAxisAlignment: MainAxisAlignment.center,
    //       children: [
    //         Container(
    //           width: 96,
    //           height: 96,
    //           decoration: BoxDecoration(
    //             shape: BoxShape.circle,
    //             // gradient: LinearGradient(
    //             //   colors: [
    //             //     AppTheme.accentColor.withAlpha(40),
    //             //     AppTheme.accentGradientEnd.withAlpha(20),
    //             //   ],
    //             //   begin: Alignment.topLeft,
    //             //   end: Alignment.bottomRight,
    //             // ),
    //             // border: Border.all(
    //             //   color: AppTheme.accentColor.withAlpha(60),
    //             //   width: 1.5,
    //             // ),
    //           ),
    //           child: const Icon(
    //             Icons.video_library_outlined,
    //             size: 44,
    //             color: Colors.white,
    //           ),
    //         ),
    //         const SizedBox(height: 24),
    //         Text(
    //           'Your library is empty',
    //           style: theme.textTheme.titleMedium?.copyWith(
    //             fontSize: 20,
    //             fontWeight: FontWeight.w700,
    //             letterSpacing: -0.3,
    //           ),
    //         ),
    //         const SizedBox(height: 8),
    //         Text(
    //           'Download your favorite videos to watch anytime, anywhere, completely offline without internet.',
    //           textAlign: TextAlign.center,
    //           style: TextStyle(
    //             fontSize: 14,
    //             color: theme.textTheme.bodySmall?.color,
    //             height: 1.4,
    //           ),
    //         ),
    //         const SizedBox(height: 28),
    //         ElevatedButton.icon(
    //           onPressed: onAddVideo,
    //           style: ElevatedButton.styleFrom(
    //             foregroundColor: AppTheme.accentColor,
    //             backgroundColor: Colors.white,
    //             padding: const EdgeInsets.symmetric(
    //               horizontal: 24,
    //               vertical: 14,
    //             ),
    //             shape: RoundedRectangleBorder(
    //               borderRadius: BorderRadius.circular(16),
    //             ),
    //             elevation: 0,
    //           ),
    //           // icon: const Icon(Icons.add_rounded, size: 20),
    //           label: const Text(
    //             'Add video',
    //             style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    //           ),
    //         ),
    //       ],
    //     ),

    //   ),
    // );