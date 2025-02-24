#All distance units are in feet and all time units are in seconds
#Typically, in hockey your stick should reach your chin. Average height of a woman is 5.33 feet, so to the chin would be approximately 4.66 feet.
#Skates add maybe 3 inches to that, thus around 5 ft. Length of an arm will add approximately 20 inches. Thus we approximate the maximum stick+arm reach to be 6.5 feet
stick = 6.5

#Looking at all direct passes with an (x1,y1,frame1) and (x2,y2,frame2), we can get a five number summary of 
#(Min=0.9677,Q1=33.7695,Q2=43.1220,Mean=42.8177,Q3=53.1812,Max=94.2355). 
#We chose to set the speed of the puck as 
  #90 feet/s show what happens in the case where you sent a good hard pass
  #55 feet/s show what happens in the case where you sent a reasonably pass
  #40 feet/s show what happens in the case where you sent an average pass

#Stathletes frame rate for their tracking data
frame_rate = 1/30 # 30 frames per second, value used as tres (Alon: We might want to use a different time for this) 
                  # in time_center_radius and player_arrival_times
time_penalty = 1/10
max_velocity=35.5#30 # maximum skater velocity in ft/sec
a = 1.3 # acceleration coefficient (not directly acceleration, but more like a speed decay)
tr = 0.189 # reaction time (based on the article Phil sent)
t_max = 15 # Maximum value used to use for numerically solving arrival times 
mm = 0.1 # Coefficient of friction between puck and ice, I'll find the source for this
b = 0.1322 # Puck air drag coefficient (actuall it's the coefficient divided by the mass so beta = k/m if k is the drag coefficient)
b2 = 2.5 # pitch control coefficient used as beta in ice_ctrl_xyt and teamwise_ice_ctrl_xyt, taken from the Spearman paper
gg = 32.174 # g (as in the gravity acceleration in ft/s^2)
x_decay = 2000 #value used as decay_x
y_decay = 500 #value used as decay_y
t_rez = 1/100
goalie_dist = 8 # maximum reasonable distance for goalie to go away from goal


#offence side rink lines (upper here is in terms of x values)
upper_right_quadrant =  data.frame(
  x = c(
    172 + 28*sin(seq(pi/2,0,length=500)),
    100
  ),
  y = c(
    85 - 28 + 28*cos(seq(pi/2,0,length=500)),
    85
  )
)

lower_right_quadrant =  data.frame(
  x = c(
    100,
    172 + 28*sin(seq(0,pi/2,length=500))
  ),
  y = c(
    0, 
    0 + 28 - 28*cos(seq(0,pi/2,length=500))
  )
)

probs_to_point <- function(x_puck,y_puck, points1,all_ang, tracks1,offence,want_plot=FALSE){
  #A few minor adjustments for vectorizing the function
  points1=rbind(data.frame('theta'=double(),'x'=double(),'y'=double(),'t'=double()),points1)
  names(points1)=c('theta','x','y','t')
  points=rbind(data.frame('theta'=double(),'x'=double(),'y'=double(),'t'=double(),'all_ctrl'=double(), 'score_prob'=double(), 'pass_value'=double()),all_ang[which(round(all_ang$angle,4)==round(points1$theta,4)),])
  names(points)=c('theta','x','y','t','all_ctrl', 'score_prob', 'pass_value')
  
  #We remove the player passing the puck in our calculations as we do not want a player to "pass to themselves"
  tracks = tracks1[-which.min((tracks1$x_ft-x_puck)^2+(tracks1$y_ft-y_puck)^2),]
  
  
  #Given the team that is on the offence, identify the name of the defence
  teams = tracks$team_name %>% unique()
  defence = teams[-which(teams==offence)]
  
  #Give the current angle to pass can travel, we look at all equally spaced (through time) points along that trajectory and use the motion model
  #dist_to_xyt to determine how close the player can get to the point of interest in the given time frame
  dist_to_points = matrix(nrow=nrow(points), ncol=nrow(tracks))
  for(player in 1:nrow(tracks)){
    dist_to_points[,player]=apply(points,1,dist_to_xyt,x0=tracks$x_ft[player],y0=tracks$y_ft[player],vx=tracks$vel_x[player],vy=tracks$vel_y[player])
  }
  
  dist_to_points[,tracks$goalie] = ifelse(((points$x-189)^2 +(points$y-42.5)^2) <= goalie_dist^2,
                                          dist_to_points[,tracks$goalie],
                                          pmax(dist_to_points[,tracks$goalie],((points$x-189)^2 +(points$y-42.5)^2)^0.5-goalie_dist))
  
  #Given how close a player gets to their target, we place a Gaussian distribution at that point to add some variability to how close the player can get
  #and associate a probability to whether or not their could intercept the puck. We use stick length as the standard deviation. This is done for all players
  #except the passer for each potential intercept point along a trajectory
  #t_star = 1- pmin(abs(dist_to_points+stick)/(2*stick),1)-pmin(abs(dist_to_points-stick)/(2*stick),1)
  
  #1-(abs(dist_to_points+stick)/stick)^3
  if(length(points$t)>1){
    norm_probs = abs(pnorm((dist_to_points+stick)/stick)-pnorm((dist_to_points-stick)/stick))*abs(points$t[2]-points$t[1])/time_penalty
  }else{
    norm_probs = abs(pnorm((dist_to_points+stick)/stick)-pnorm((dist_to_points-stick)/stick))*(points$t[1])/time_penalty
  }
  pickup_probs = norm_probs*(tracks$team_name==offence)*(1-exp(-points$t/tr))+norm_probs*(tracks$team_name!=offence)*(1-exp(-points$t/(tr+0.1)))
  
  #Combine the original (angle, x,y,t) points we are evaluating with the pickup probabilities of each player determined in the previous step

  #Split the probabilities into offence and defence
  off_lines = which(tracks$team_name==offence)
  def_lines = which(tracks$team_name!=offence)
  off_probs = pickup_probs[,off_lines]
  def_probs = pickup_probs[,def_lines]
  
  #Pre-fill a matrix with rank 1 to the number of players who can intercept the puck
  rank_mat = t(replicate(nrow(pickup_probs),tracks$team_name==offence))
  
  #Use the probabilities of each player getting to a target to rank them. The player to arrive first, has the best rank and chance to pickup the puck first
  all_rank = t(apply(-pickup_probs,1,rank))
  
  rix <-  as.vector(t(replicate(ncol(pickup_probs),seq(1,nrow(pickup_probs),1))))
  
  #Each player following the highest rank has a smaller chance at getting the puck because it is conditional on the player before they getting to that point and missing
  #We update the probability player i picks up the puck using p_i(new)=p_i(old)*product_j=1^i-1 of (1-p_j)
  ranked_probs <-  pickup_probs * 0
  ranked_probs[cbind(rix,as.vector(t(all_rank)))] <- as.vector(t(pickup_probs))
  if(ncol(ranked_probs)>1){
    ranked_probs[,2] = ranked_probs[,2]*(1-ranked_probs[,1])
    if(ncol(ranked_probs)>2){
      for (c in 3:ncol(ranked_probs)){
        if (nrow(ranked_probs)>1){
          ranked_probs[,c] = ranked_probs[,c]*(1-rowSums(ranked_probs[,1:(c-1)]))
        }else{
          ranked_probs[,c] = ranked_probs[,c]*(1-sum(ranked_probs[,1:(c-1)]))
        }
        
      }
    }
  }
  
  #Similarly to above, if there are n_p points along the trajectory, the chance someone picks up the puck at the 3rd point is conditional on no one getting the puck
  #at points 1 or 2. We update these probabilities using the same method as above.
  ranked_off_mat <- rank_mat * 0
  ranked_off_mat[cbind(rix,as.vector(t(all_rank)))] <- as.vector(t(rank_mat))
  pass_probs <- data.frame(off = rowSums(ranked_probs * ranked_off_mat),
                           def = rowSums(ranked_probs * (1-ranked_off_mat))) %>% 
    mutate(None = pmax(1 - off - def,0))
  #pass_probs$None = ifelse(pass_probs$None<0,0,pass_probs$None) # fix for rounding errors
  adj_offence = pass_probs$off
  if(nrow(pass_probs)>1){
    for (r in 2:nrow(pass_probs)){
      pass_probs[r,] = pass_probs[r,] * pass_probs$None[r-1]
    }
  }
  
  #Finalize the summary data that has been collected for each point along the trajectory and it's probability of being picked up the offence, defence and no one
  #Additionally the points data.frame includes previously calculated...
  #all_ctrl:
  #score_prob:
  #pass_value:
  all_data_probs <- cbind(points,pass_probs)
  colnames(all_data_probs) <- c("theta","x","y","t","all_ctrl","score_prob","pass_value","off","def","None")
  
  #To give one summary statistic for each point along the trajectory, we determine
  
  #the probability that the offence successfully retrieved the puck along the way
  cum_pass_off = cumsum(all_data_probs$off)
  cum_pass_def = cumsum(all_data_probs$def)
  #the quality of the point by determining how valuable the target multiplied by offensive pickup probability along the way
  cum_pass_good = all_data_probs$pass_value*cum_pass_off
  
  
  adj_pass_value = all_data_probs$pass_value*adj_offence
  location_pass_value = all_data_probs$pass_value*all_data_probs$off
  keep_possesion_prob = cumsum(all_data_probs$off)
  
  expected_pass_value = sum(location_pass_value)
  max_pass_value = max(all_data_probs$pass_value)
  best_case_pass_value = max(adj_pass_value)
  successful_pass_prob = sum(all_data_probs$off)
  
  mat_to_return = cbind(points,adj_pass_value,off_prob=all_data_probs$off,def_prob=all_data_probs$def,none_prob=all_data_probs$None,location_pass_value,keep_possesion_prob,expected_pass_value=expected_pass_value,max_pass_value=max_pass_value,best_case_pass_value=best_case_pass_value,successful_pass_prob=successful_pass_prob)
  if(want_plot){
    #If desired, we can plot the individual trajectory to look at all points along that path which we are calculating values for
    plot_pass=plot_half_rink(ggplot(tracks1)) +
      geom_point(data = points, aes(x = x, y = y), size = 2, shape = 4, colour='dark grey') + 
      geom_segment(aes(x = x_puck, y = y_puck, xend = puck$x_ft, yend = puck$y_ft),size=1.5, colour='brown')+
      geom_point(aes(x = x_puck, y = y_puck), size = 2, shape = 16, colour='black') + 
      geom_segment(aes(x = x_ft, y = y_ft, xend = x_ft+vel_x, yend = y_ft+vel_y), #/sqrt(vel_x^2+vel_y^2) to get r=1
                   arrow = arrow(length = unit(0.2, "cm")),size=1, colour='cyan') + 
      geom_point(aes(x = x_ft, y = y_ft, fill = team_name), size = 5, shape = 21) +
      geom_text(aes(x = x_ft, y = y_ft, label = jersey_number, colour = team_name), size = 3) +
      geom_point(data = points, aes(x = x, y = y), colour='dark grey',size = 1, shape = 16) +
      scale_colour_manual(values = c("Switzerland" = "white", "Finland" = "white")) +
      scale_fill_manual(values = c("Switzerland" = "red", "Finland" = "blue")) +
      geom_segment(data = points,aes(x = x_puck, y = y_puck, xend = x, yend = y),linetype=2)+
      labs(fill = "Team") +
      guides(colour = "none") 
    return(list(mat_to_return,plot_pass))
  }else{
    return(mat_to_return)
  }
}


#Statletes provided code for plotting the full rink. Dims x=200 ft wide and y=85 ft high
plot_rink = function(p_object){
  require(ggforce)
  require(cowplot)
  require(tidyverse)
  upper_outline = data.frame(
    x = c(
      115,
      172 + 28*sin(seq(0,pi/2,length=20)),
      172 + 28*sin(seq(pi/2,0,length=20)),
      115
    ),
    y = c(
      0, 
      0 + 28 - 28*cos(seq(0,pi/2,length=20)),
      85 - 28 + 28*cos(seq(pi/2,0,length=20)),
      85
    )
  )
  
  lower_outline = data.frame(
    x = c(
      115,
      100-72 - 28*sin(seq(0,pi/2,length=20)),
      100-72 - 28*sin(seq(pi/2,0,length=20)),
      115
    ),
    y = c(
      0, 
      0 + 28 - 28*cos(seq(0,pi/2,length=20)),
      85 - 28 + 28*cos(seq(pi/2,0,length=20)),
      85
    )
  )
  
  p = p_object +
    ## FACEOFF CIRCLES ##
    geom_circle(data = data.frame(x0 = 100, y0 = 42.5, r = 15), aes(x0 = x0, y0 = y0, r = r), lwd = 0.5, col = "gray50", inherit.aes = FALSE) +
    geom_circle(data = data.frame(x0 = 169, y0 = 20.5, r = 15), aes(x0 = x0, y0 = y0, r = r), lwd = 0.5, col = "gray50", inherit.aes = FALSE) +
    geom_circle(data = data.frame(x0 = 169, y0 = 64.5, r = 15), aes(x0 = x0, y0 = y0, r = r), lwd = 0.5, col = "gray50", inherit.aes = FALSE) +
    geom_circle(data = data.frame(x0 = 31, y0 = 64.5, r = 15), aes(x0 = x0, y0 = y0, r = r), lwd = 0.5, col = "gray50", inherit.aes = FALSE) +
    geom_circle(data = data.frame(x0 = 31, y0 = 20.5, r = 15), aes(x0 = x0, y0 = y0, r = r), lwd = 0.5, col = "gray50", inherit.aes = FALSE) +
    ## FACEOFF DOTS ##
    geom_point(inherit.aes = FALSE, aes(y = 42.5, x = 100), col = "gray50", size = 1) +
    geom_point(inherit.aes = FALSE, aes(y = 20.5, x = 169), col = "gray50", size = 1) +
    geom_point(inherit.aes = FALSE, aes(y = 64.5, x = 169), col = "gray50", size = 1) +
    geom_point(inherit.aes = FALSE, aes(y = 20.5, x = 120), col = "gray50", size = 1) +
    geom_point(inherit.aes = FALSE, aes(y = 64.5, x = 120), col = "gray50", size = 1) +
    geom_point(inherit.aes = FALSE, aes(y = 20.5, x = 31), col = "gray50", size = 1) +
    geom_point(inherit.aes = FALSE, aes(y = 64.5, x = 31), col = "gray50", size = 1) +
    geom_point(inherit.aes = FALSE, aes(y = 20.5, x = 80), col = "gray50", size = 1) +
    geom_point(inherit.aes = FALSE, aes(y = 64.5, x = 80), col = "gray50", size = 1) +
    ## BLUE AND RED LINES ##
    annotate("segment", col = "gray50",  x = 75, xend = 75, y = 0, yend = 85, lwd = 0.5) +
    annotate("segment", col = "gray50", x = 100, xend = 100, y = 0, yend = 85, lwd = 0.5) +
    annotate("segment", col = "gray50",  x = 125, xend = 125, y = 0, yend = 85, lwd = 0.5) +
    ## NET AND GOAL LINE ##
    geom_segment(col = "gray50", inherit.aes = FALSE, lwd = 0.5, aes(y = 79.25, x = 11, yend = 5.75, xend = 11)) +
    geom_segment(col = "indianred", inherit.aes = FALSE, lwd = 0.5, aes(y = 39.5, x = 7.5, yend = 45.5, xend = 7.5)) + 
    geom_segment(col = "indianred", inherit.aes = FALSE, lwd = 0.5, aes(y = 39.5, x = 7.5, yend = 39.5, xend = 11)) +  
    geom_segment(col = "indianred", inherit.aes = FALSE, lwd = 0.5, aes(y = 45.5, x = 7.5, yend = 45.5, xend = 11)) +
    geom_segment(col = "gray50", inherit.aes = FALSE, lwd = 0.5, aes(y = 5.75, x = 189, yend = 79.25, xend = 189)) +
    geom_segment(col = "indianred", inherit.aes = FALSE, lwd = 0.5, aes(y = 39.5, x = 192.5, yend = 45.5, xend = 192.5)) + 
    geom_segment(col = "indianred", inherit.aes = FALSE, lwd = 0.5, aes(y = 39.5, x = 192.5, yend = 39.5, xend = 189)) +  
    geom_segment(col = "indianred", inherit.aes = FALSE, lwd = 0.5, aes(y = 45.5, x = 192.5, yend = 45.5, xend = 189)) +
    ## OUTLINE ##
    geom_path(data = upper_outline, aes(x = x, y = y), colour = "gray80", inherit.aes = FALSE, lwd = 0.5) +
    geom_path(data = lower_outline, aes(x = x, y = y), colour = "gray80", inherit.aes = FALSE, lwd = 0.5) +
    ## ADDITIONAL SPECS ##
    scale_x_continuous(expand = c(0, 0), limits = c(0,200)) + scale_y_continuous(expand = c(0,0), limits = c(0,85)) +
    coord_fixed() +
    theme_void()
  
  return(p)
}

#Adjustment of stathletes code to plot only the blue line to the attacking net that the play takes place in
plot_half_rink = function(p_object){
  
  require(ggforce)
  require(cowplot)
  require(tidyverse)
  
  upper_outline = data.frame(
    x = c(
      100,
      172 + 28*sin(seq(0,pi/2,length=20)),
      172 + 28*sin(seq(pi/2,0,length=20)),
      100
    ),
    y = c(
      0, 
      0 + 28 - 28*cos(seq(0,pi/2,length=20)),
      85 - 28 + 28*cos(seq(pi/2,0,length=20)),
      85
    )
  )
  
  lower_outline = data.frame(
    x = c(
      100,
      100-72 - 28*sin(seq(0,pi/2,length=20)),
      100-72 - 28*sin(seq(pi/2,0,length=20)),
      100
    ),
    y = c(
      0, 
      0 + 28 - 28*cos(seq(0,pi/2,length=20)),
      85 - 28 + 28*cos(seq(pi/2,0,length=20)),
      85
    )
  )
  
  p = p_object +
    ## FACEOFF CIRCLES ##
    geom_circle(data = data.frame(x0 = 169, y0 = 20.5, r = 15), aes(x0 = x0, y0 = y0, r = r), lwd = 0.5, col = "gray50", inherit.aes = FALSE) +
    geom_circle(data = data.frame(x0 = 169, y0 = 64.5, r = 15), aes(x0 = x0, y0 = y0, r = r), lwd = 0.5, col = "gray50", inherit.aes = FALSE) +
    ## FACEOFF DOTS ##
    geom_point(inherit.aes = FALSE, aes(y = 20.5, x = 169), col = "gray50", size = 1) +
    geom_point(inherit.aes = FALSE, aes(y = 64.5, x = 169), col = "gray50", size = 1) +
    ## BLUE AND RED LINES ##
    annotate("segment", col = muted("dark blue"),  x = 125, xend = 125, y = 0, yend = 85, lwd = 3) +
    ## NET AND GOAL LINE ##
    geom_segment(col = muted("dark red"), inherit.aes = FALSE, lwd = 1.5, aes(y = 5.75, x = 189, yend = 79.25, xend = 189)) +
    geom_segment(col = "indianred", inherit.aes = FALSE, lwd = 0.5, aes(y = 39.5, x = 192.5, yend = 45.5, xend = 192.5)) + 
    geom_segment(col = "indianred", inherit.aes = FALSE, lwd = 0.5, aes(y = 39.5, x = 192.5, yend = 39.5, xend = 189)) +  
    geom_segment(col = "indianred", inherit.aes = FALSE, lwd = 0.5, aes(y = 45.5, x = 192.5, yend = 45.5, xend = 189)) +
    ## OUTLINE ##
    geom_path(data = upper_outline, aes(x = x, y = y), colour = "gray80", inherit.aes = FALSE, lwd = 2) +
    ## ADDITIONAL SPECS ##
    scale_x_continuous(expand = c(0, 0), limits = c(100,201)) + scale_y_continuous(expand = c(0,0), limits = c(-1,86)) +
    coord_fixed() +
    theme_void()
  
  return(p)
}

# Function to save the ggplot of interest to mp4, can be changed to gif if desired
save_play <- function(data, r, t_start, type){
  line1 <- paste('data$relevant_events$\'',r,'\'$tracks$\'',t_start,'\'',sep='')
  line2 <- eval(parse(text=line1))
  if(length(line2$frame_id)!=0){
    json_tracks <- lapply(line2, function(x) {
      x[sapply(x, is.null)] <- NA
      unlist(x)
    })
    tracking_data <- as.data.frame(do.call("cbind", json_tracks))
    tracking_data <- tracking_data[,c('frame_id','period','track_id','team_id','team_name','jersey_number','x_ft','y_ft')]
    rownames(tracking_data) = NULL
    teams <- unique(tracking_data$team_name)
    team1 <- teams[1]
    team2 <- teams[2]
    title = paste("PP", r, "_", team1, "_", team2, "_SS", t_start, sep = "")
    
    tracking_data$frame_id = tracking_data$frame_id %>% as.integer()
    #tracking_data$frame_id = tracking_data$frame_id - min(tracking_data$frame_id)+1
    tracking_data$period = tracking_data$period %>% as.integer()
    tracking_data$track_id = tracking_data$track_id %>% as.integer()
    tracking_data$team_id = tracking_data$team_id %>% as.character()
    tracking_data$team_name = tracking_data$team_name %>% as.character()
    tracking_data$jersey_number = tracking_data$jersey_number %>% as.integer()
    tracking_data$x_ft = tracking_data$x_ft %>% as.double()
    tracking_data$y_ft = tracking_data$y_ft %>% as.double()

    ## ANIMATED PLOTS ##
    
    # Set the specs for the gif we want to create (lower res to make it run quicker)
    options(gganimate.dev_args = list(width = 10, height = 6, units = 'in', res = 320))
    
    # Source in the plot_rink function
    #source("C:/Users/Paula/Desktop/Big-Data-Cup-2022-Private/OTTHAC_Tutorial/Code/plot_rink.R")
    #source("/Volumes/BRICK_HOUSE/Hockey/Big-Data-Cup-2022-Private-main/OTTHAC_Tutorial/Code/plot_rink.R")
    
    # Create a gif of this play
    p = plot_rink(ggplot(tracking_data)) +
      geom_point(aes(x = x_ft, y = y_ft, fill = team_name), shape = 21, size = 6) +
      geom_text(aes(x = x_ft, y = y_ft, label = jersey_number, colour = team_name), size = 3) +
      scale_colour_manual(values = c("USA" = "white", "Canada" = "white")) +
      scale_fill_manual(values = c("USA" = "blue", "Canada" = "red")) +
      # Additional specs
      geom_text(aes(x = 25, y = 40, label = frame_id), size = 5) +
      transition_time(frame_id) + 
      labs(fill = "Team") +
      guides(colour = "none")
    
    
    # Get the maximum and minimum frame number (so we know how long the gif should be)
    max_frame = tracking_data$frame_id %>% max()
    min_frame = tracking_data$frame_id %>% min() 
    
    # Render the animation
    if(type == "mp4"){
    # Save as mp4
      p2 = animate(p, renderer = ffmpeg_renderer(), fps = 30, duration = (max_frame - min_frame+1)/30)#((max_frame - min_frame)/30 + 1))
      anim_save(paste(title,".mp4",sep=""), p2)
    #
    }else{
    #Save as gif
      anim_save(paste(title,".gif",sep=""), p, fps = 30, duration = (max_frame - min_frame+1)/30)
    }
  }
}


# This function gives the distance a player would be from a target point
# given starting location and velocity and a target time t 
dist_to_xyt <- function(xyt,x0,y0,vx,vy, vmax = max_velocity, alpha = a, t_r =  tr){
  
  # xyt - triplet of x y t of desired location and time
  # x0,y0 - current location
  # vx,vy - current speeD
  # vmax - maximum speed
  # alpha - decay coefficient (related to acceleration)
  # t_r - reaction time
  tx <- xyt['x']
  ty <- xyt['y']
  t <- xyt['t']
  
  
  # If time is smaller than reaction time, skater keeps going at initial speed
  if (t<t_r){
    c_x = x0 +vx * t
    c_y = y0 + vy * t
    r = 0
    }
  #first accounting for reaction time
  else{
    x0 = x0 + t_r * vx
    y0 = y0 + t_r * vy
    t = t - t_r
  
  # Now building the motion model for the remaining time
  
    c_x = x0 + vx * (1-exp(-alpha * t))/alpha
    c_y = y0 + vy * (1-exp(-alpha * t))/alpha
    r = vmax * (t - (1-exp(-alpha * t))/alpha)
  }
  
  remaining_dist = ((tx-c_x)^2 + (ty-c_y)^2)^0.5-r
  return(max(remaining_dist,0))
  
}

time_center_radius <- function(x0,y0,vx,vy, vmax = max_velocity, alpha = a, t_r =  tr, tmax = t_max, tres = t_rez){ 
  # Motion function model - returns player's center location and possible arrival 
  #                         radius over time, given initial conditions 
  
  
  ti <- seq(0,t_r,tres) # initial time - before reaction
  tr <- seq(0,10-t_r,tres)# reamining time after reaction
  
  c_xi <- x0 + ti * vx
  c_yi <- y0 + ti *vy
  r_i <- 0 * ti
  
  x0 = x0 + t_r * vx
  y0 = y0 + t_r * vy
  
  # Now building the motion model for the remaining time
  
  c_xr = x0 + vx * (1-exp(-alpha * tr))/alpha
  c_yr = y0 + vy * (1-exp(-alpha * tr))/alpha
  r_r = vmax * (tr - (1-exp(-alpha * tr))/alpha)
  
  c_xf <- c(c_xi,c_xr)
  c_yf <- c(c_yi,c_yr)
  r_f <- c(r_i,r_r)
  
  t <- c(ti, tr+t_r)
  
  return(data.frame(t = t, cx = c_xf, cy = c_yf, r = r_f))
  
}

t_reach <- function(loc, t_c_r, goalie_flag = F, goalie_radius = goalie_dist){
  # Motion model function -  Measure time for arrival of player at given location
  tx = loc[1]
  ty = loc[2]
  goalie_delay = 1
  if ((ty-42.5)^2+(tx-189)^2 > goalie_radius^2 & goalie_flag){
    extra_distance <- ((ty-42.5)^2+(tx-189)^2)^0.5 - goalie_radius
    goalie_delay <- exp(extra_distance/goalie_radius)
  }
  remaining_dist = ((tx-t_c_r$cx)^2 + (ty-t_c_r$cy)^2)^0.5-t_c_r$r-3
  # print(remaining_dist)
  # ix  <- max(which(remaining_dist>0))
  # return(ifelse(ix == -Inf, 0, t_c_r$t[ix+1] * goalie_delay))
  return(ifelse(max(remaining_dist)<0, 0, t_c_r$t[max(which(remaining_dist>0))+1] * goalie_delay))
}

player_arrival_times <- function(x0,y0,vx,vy,
                                 grid = expand.grid(x = seq(0,200,0.5), y = seq(0,85,0.5)),
                                 vmax = max_velocity,
                                 alpha = a, 
                                 t_r = tr,
                                 tmax = t_max, 
                                 tres = t_rez,
                                 goalie = F
                                 ){
  # Motion model function - measure arrival times set of points x,y,t
  t_c_r <- time_center_radius(x0, y0, vx, vy)
  times <- apply(grid,1,t_reach,t_c_r,goalie_flag = goalie)
  # print(times)
  return(cbind(grid, arr_times = times))
}

ice_ctrl_xyt <- function(loc_vel,xyt,vmax = max_velocity, alpha = a, t_r = tr, beta = b2){
  # Rink Control function - Calculate Rink Control contribution of one player, in entire grid
  x0 <- loc_vel['x_ft']
  y0 <-  loc_vel['y_ft']
  vx <- loc_vel['vel_x']
  vy <- loc_vel['vel_y']
  goalie_flag <- loc_vel['goalie']
  grid <- xyt %>% select(x,y)
  x_y_tarr <- player_arrival_times(x0,y0,vx,vy,grid = grid, goalie = goalie_flag)
  x_y_tarr$arr_times = pmax(x_y_tarr$arr_times - xyt$t, 0.001)
  
  return(ctrl = loc_vel['team_label'] * x_y_tarr$arr_times ^ (-beta))
}


teamwise_ice_ctrl_xyt <- function(loc_vel,xyt,vmax = max_velocity, alpha = a, t_r = tr, beta = b2){
  # Rink Control function - Calculate full Rink Control, accounting for all available players
  ctrl <- apply(loc_vel, 1, ice_ctrl_xyt, xyt, vmax, alpha, t_r, beta)
  return(ice_ctrl = rowSums(ctrl)/rowSums(abs(ctrl)))
}

score_prob <- function(xyt, decay_x = x_decay, decay_y = y_decay){
  # Scoring Probability function 
  x = xyt['x']
  y = xyt['y']
  Prob <- (abs((189-x)/sqrt((42.5-y)^2+(189-x)^2))+1)/ifelse(x>189,8,4)*exp(-((189-x)^2/decay_x +(42.5-y)^2/decay_y))
  
  return(Prob)
  
}

puck_motion_model <- function(x0,y0,vx,vy, t = time_step, mu = mm, beta = b, g = gg){
  # Puck Motion Model function - return puck's x,y,t given starting conditions/
  #                              Uses vx, vy to describe initial velocity
  
  vmag <-  sqrt(vx^2 + vy^2)
  
  x <-  x0 + (vx + mu*g * vx/vmag/beta) * (1 - exp(-beta * t))/beta - (mu*g * vx/vmag)/beta * t
  y <-  y0 + (vy + mu*g * vy/vmag/beta) * (1 - exp(-beta * t))/beta - (mu*g * vy/vmag)/beta * t
  
  return(data.frame(x = x, y = y, t = t))
}

puck_motion_model2 <- function(x0,y0,angle,vmag=speed_puck, t = time_step, mu = mm, beta = b, g = gg){
  # Puck Motion Model function - return puck's x,y,t given starting conditions/
  #                              Uses vmag, angle to describe intial velocity
  
  vx = vmag*sin(angle)
  vy = vmag*cos(angle)
  
  x <-  x0 + (vx + mu*g * vx/vmag/beta) * (1 - exp(-beta * t))/beta - (mu*g * vx/vmag)/beta * t
  y <-  y0 + (vy + mu*g * vy/vmag/beta) * (1 - exp(-beta * t))/beta - (mu*g * vy/vmag)/beta * t
  
  return(data.frame(x = x, y = y, t = t))
}


clean_pass <- function(passes, xmin=100, xmax=200, ymin=0, ymax=85){
  # Motion Model Function - Clears out any values that end up outside the given boarders
  passes1 <- passes %>% filter(xmin<x) %>% filter(ymin<y) %>% filter(x<xmax) %>% filter(y<ymax)
  
  return(passes1)
}

calc_vmag_ang = function(events, mu = mm, beta = b, g = gg){
  # Calculate actual pass's initial speed and angle from event data using puck motion model
  
  out <- events %>% mutate(x_coord = as.double(x_coord),x_coord_2 = as.double(x_coord_2), 
                           y_coord = as.double(y_coord),y_coord_2 = as.double(y_coord_2),
                           frame_id_1 = as.double(frame_id_1), frame_id_2 = as.double(frame_id_2))%>% 
    mutate(delta_x = x_coord_2 - x_coord, delta_y = y_coord_2 - y_coord,
           delta_t = (frame_id_2 - frame_id_1)*frame_rate) %>% 
    mutate(delta_r = (delta_x^2 + delta_y^2)^0.5,
           ang = (atan(delta_x/delta_y) + ifelse(delta_y<0,pi,0)+pi) %% (2*pi) - pi) %>%
    mutate(vmag = (delta_r * beta + mu * g * delta_t)/(1-exp(-beta * delta_t)) - mu *g /beta) %>% 
    select(vmag, ang) # Comment this out to get a full data frame with all the additional calculations (delta_x/y/t/r)
  return(out)
}

inside_boards_point <- function(xy){
  # Check's that a point x,y is inside the board for the curved part of the ice
  # Works in conjunction with clean pass to remove all defensive passes and other
  # illegal locations
  x = xy['x']
  y = xy['y']
  
  radius = (x>172)*((y>57)*((x-172)^2 + (y-57)^2)^0.5 + (y<28)*((x-172)^2 + (28-y)^2)^0.5)
  return(radius<=28)
  # 
  # return(!any(((x>lower_right_quadrant$x) & (y<lower_right_quadrant$y)) | ((x>upper_right_quadrant$x) & (y>upper_right_quadrant$y))))
  
}

filter_inside_boards <-function(df){
  # Filter larger df using inside_boards_point - df must have 'x' and 'y' columns
  in_rink = apply(df,1,inside_boards_point)
  return(df[in_rink,])
}

fill_missing_players <- function(one_event, tracking_data){
  # Add passer or receiver of pass from event data to tracking data if missing
  
  pl1_num = one_event[['Player_1_num']]
  pl2_num = one_event[['Player_2_num']]
  off_team = one_event[['team_name']]
  
  team_tracks = tracking_data %>% filter(team_name == off_team)
  
  if (!(pl1_num %in% team_tracks$jersey_number)){
    temp_track = team_tracks[1,]
    temp_track['x_ft'] = one_event['x_coord']
    temp_track['y_ft'] = one_event['y_coord']
    temp_track['jersey_number'] = pl1_num
    temp_track['vel_x'] = 0.05
    temp_track['vel_y'] = 0.05
    temp_track['track_id'] = -1
    temp_track['goalie'] = FALSE
    tracking_data = tracking_data %>% rbind(temp_track)
  }
  
  if (!(pl2_num %in% team_tracks$jersey_number)){
    temp_track = team_tracks[1,]
    temp_track['x_ft'] = one_event['x_coord_2']
    temp_track['y_ft'] = one_event['y_coord_2']
    temp_track['jersey_number'] = pl2_num
    temp_track['vel_x'] = 0.05
    temp_track['vel_y'] = 0.05
    temp_track['track_id'] = -2
    temp_track['goalie'] = FALSE
    tracking_data = tracking_data %>% rbind(temp_track)
  }
  
  return(tracking_data)
  
}


